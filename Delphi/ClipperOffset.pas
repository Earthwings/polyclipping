unit ClipperOffset;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  16 September 2017                                               *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************)

{$IFDEF FPC}
  {$DEFINE INLINING}
{$ELSE}
  {$IF CompilerVersion < 14}
    Requires Delphi version 6 or above.
  {$IFEND}
  {$IF CompilerVersion >= 18}         //Delphi 2007
    //While Inlining has been supported since D2005, both D2005 and D2006
    //have an Inline codegen bug (QC41166) so ignore Inline until D2007.
    {$DEFINE INLINING}
    {$IF CompilerVersion >= 25.0}     //Delphi XE4+
      {$LEGACYIFEND ON}
    {$IFEND}
  {$IFEND}
{$ENDIF}

interface

uses
  SysUtils, Types, Classes, Math, Clipper, ClipperMisc;

type

  TJoinType = (jtSquare, jtRound, jtMiter);
  TEndType = (etPolygon, etOpenJoined, etOpenButt, etOpenSquare, etOpenRound);

  TPointD = record X, Y: Double; end;
  TArrayOfPointD = array of TPointD;

  TClipperOffset = class
  private
    FDelta: Double;
    FSinA, FSin, FCos: Extended;
    FMiterLim, FMiterLimit: Double;
    FStepsPerRad: Double;
    FNorms: TArrayOfPointD;
    FSolution: TPaths;
    FOutPos: Integer;
    FPathIn: TPath;
    FPathOut: TPath;

    FLowestIdx: Integer; //index to the path with the lowermost vertex
    FNodeList: TList;
    FArcTolerance: Double;

    procedure AddPoint(const pt: TPoint64);
    procedure DoSquare(j, k: Integer);
    procedure DoMiter(j, k: Integer; cosAplus1: Double);
    procedure DoRound(j, k: Integer);
    procedure OffsetPoint(j: Integer;
      var k: Integer; JoinType: TJoinType);

    procedure GetLowestPolygonIdx;
    procedure DoOffset(delta: Double);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddPath(const p: TPath; jt: TJoinType; et: TEndType);
    procedure AddPaths(const p: TPaths; jt: TJoinType; et: TEndType);
    procedure Clear;
    procedure Execute(out solution: TPaths; delta: Double);
    property MiterLimit: Double read FMiterLimit write FMiterLimit;
    property ArcTolerance: Double read FArcTolerance write FArcTolerance;
  end;

  function OffsetPaths(const paths: TPaths;
    delta: Double; jt: TJoinType; et: TEndType): TPaths;

implementation

//OVERFLOWCHECKS OFF is a necessary workaround for a Delphi compiler bug that very
//occasionally reports overflow errors while still returning correct values
//eg var A, B: Int64; begin A := -$13456780; B := -$73456789; A := A * B; end;
//see https://forums.embarcadero.com/message.jspa?messageID=871444
//nb: this issue was resolved in Delphi 10.2
{$OVERFLOWCHECKS OFF}

type
  TPathNode = class
  private
    FPath      : TPath;
    FJoinType  : TJoinType;
    FEndType   : TEndType;
    fLowestIdx : Integer;
  public
    constructor  Create(const p: TPath; jt: TJoinType; et: TEndType);
  end;

resourcestring
  rsClipperOffset = 'ClipperOffset error';

const
  Tolerance           : Double = 1.0E-15;
  DefaultArcFrac      : Double = 0.02;
  Two_Pi              : Double = 2 * PI;
  LowestIp            : TPoint64 = (X: High(Int64); Y: High(Int64));

//------------------------------------------------------------------------------
//  Miscellaneous offset support functions
//------------------------------------------------------------------------------

function PointD(const X, Y: Double): TPointD; overload;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function PointD(const pt: TPoint64): TPointD; overload;
begin
  Result.X := pt.X;
  Result.Y := pt.Y;
end;
//------------------------------------------------------------------------------

function GetUnitNormal(const pt1, pt2: TPoint64): TPointD;
var
  dx, dy, inverseHypot: Double;
begin
  if (pt2.X = pt1.X) and (pt2.Y = pt1.Y) then
  begin
    Result.X := 0;
    Result.Y := 0;
    Exit;
  end;

  dx := (pt2.X - pt1.X);
  dy := (pt2.Y - pt1.Y);
  inverseHypot := 1 / Hypot(dx, dy);
  dx := dx * inverseHypot;
  dy := dy * inverseHypot;
  Result.X := dy;
  Result.Y := -dx
end;

//------------------------------------------------------------------------------
//  TPathNode methods
//------------------------------------------------------------------------------

constructor  TPathNode.Create(const p: TPath; jt: TJoinType; et: TEndType);
var
  i, lenP, last: Integer;
begin
  inherited Create;
  FPath := nil;
  FJoinType := jt;
  FEndType := et;

  lenP := length(p);
  if (et = etPolygon) or (et = etOpenJoined) then
    while (lenP > 1) and PointsEqual(p[lenP-1], p[0]) do dec(lenP)
  else if (lenP = 2) and PointsEqual(p[1], p[0]) then
    lenP := 1;

  if lenP = 0 then
    Exit
  else if (lenP < 3) and ((et = etPolygon) or (et = etOpenJoined)) then
  begin
    if jt = jtRound then FEndType := etOpenRound
    else FEndType := etOpenSquare;
  end;

  setLength(fPath, lenP);
  fPath[0] := p[0];
  last := 0;
  FLowestIdx := 0;
  for i := 1 to lenP -1 do
  begin
    if PointsEqual(fPath[last], p[i]) then Continue;
    inc(last);
    fPath[last] := p[i];
    if (FEndType <> etPolygon) then Continue;
    if (p[i].Y >= fPath[fLowestIdx].Y) and
      ((p[i].Y > fPath[fLowestIdx].Y) or (p[i].X < fPath[fLowestIdx].X)) then
        fLowestIdx := i;
  end;
  setLength(fPath, last +1);
  if (FEndType = etPolygon) and (last < 2) then FPath := nil;
  //note open paths can have just a single vertex.
end;

//------------------------------------------------------------------------------
// TClipperOffset methods
//------------------------------------------------------------------------------

constructor TClipperOffset.Create;
begin
  inherited Create;
  FNodeList := TList.Create;
  FMiterLimit := 2;
  FArcTolerance := 0;
end;
//------------------------------------------------------------------------------

destructor TClipperOffset.Destroy;
begin
  Clear;
  FNodeList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.Clear;
var
  i: Integer;
begin
  for i := 0 to FNodeList.Count -1 do
    TPathNode(FNodeList[i]).Free;
  FNodeList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.AddPath(const p: TPath; jt: TJoinType; et: TEndType);
var
  pn: TPathNode;
begin
  pn := TPathNode.Create(p, jt, et);
  if pn.FPath = nil then pn.Free
  else FNodeList.Add(pn);
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.AddPaths(const p: TPaths; jt: TJoinType; et: TEndType);
var
  i: Integer;
begin
  for i := 0 to High(p) do AddPath(p[i], jt, et);
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.GetLowestPolygonIdx;
var
  i: Integer;
  node: TPathNode;
  ip1, ip2: TPoint64;
begin
  FLowestIdx := -1;
  for i := 0 to FNodeList.Count -1 do
  begin
    node := TPathNode(FNodeList[i]);
    if (node.FEndType <> etPolygon) then Continue;
    if fLowestIdx < 0 then
    begin
      ip1 := node.FPath[node.FLowestIdx];
      FLowestIdx := i;
    end else
    begin
      ip2 := node.FPath[node.FLowestIdx];
      if (ip2.Y >= ip1.Y) and
        ((ip2.Y > ip1.Y) or (ip2.X < ip1.X)) then
      begin
        FLowestIdx := i;
        ip1 := ip2;
      end;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.DoOffset(delta: Double);
var
  i, j, k, pathLen, solCnt: Integer;
  X, X2, Y, arcTol, absDelta, steps: Double;
  node: TPathNode;
  norm: TPointD;
begin
  FSolution := nil;
  FDelta := delta;
  absDelta := Abs(delta);

  //if a Zero offset, then just copy CLOSED polygons to FSolution and return ...
  if absDelta < Tolerance then
  begin
    solCnt := 0;
    SetLength(FSolution, FNodeList.Count);
    for i := 0 to FNodeList.Count -1 do
      if (TPathNode(FNodeList[i]).FEndType = etPolygon) then
      begin
        FSolution[solCnt] := TPathNode(FNodeList[i]).FPath;
        inc(solCnt);
      end;
    SetLength(FSolution, solCnt);
    Exit;
  end;

  //FMiterLimit: see offset_triginometry3.svg
  if FMiterLimit > 1 then FMiterLim := 2/(sqr(FMiterLimit))
  else FMiterLim := 2;

  if (FArcTolerance <= DefaultArcFrac) then
    arcTol := absDelta * DefaultArcFrac else
    arcTol := FArcTolerance;


  //see offset_triginometry2.svg
  steps := PI / ArcCos(1 - arcTol / absDelta);  //steps per 360 degrees
  if (steps > absDelta * Pi) then
    steps := absDelta * Pi;                //ie excessive precision check

  Math.SinCos(Two_Pi / steps, FSin, FCos); //sin & cos per step
  if delta < 0 then FSin := -FSin;
  FStepsPerRad := steps / Two_Pi;

  SetLength(FSolution, FNodeList.Count * 2);
  solCnt := 0;
  for i := 0 to FNodeList.Count -1 do
  begin
    node := TPathNode(FNodeList[i]);
    FPathIn := node.FPath;
    pathLen := length(FPathIn);

    FOutPos := 0;
    FPathOut := nil;

    //if a single vertex then build circle or a square ...
    if (pathLen = 1) then
    begin
      if node.FJoinType = jtRound then
      begin
        X := 1; Y := 0;
        for j := 1 to Round(steps) do
        begin
          AddPoint(Point64(
            Round(FPathIn[0].X + X * FDelta),
            Round(FPathIn[0].Y + Y * FDelta)));
          X2 := X;
          X := X * FCos - FSin * Y;
          Y := X2 * FSin + Y * FCos;
        end
      end else
      begin
        X := -1; Y := -1;
        for j := 1 to 4 do
        begin
          AddPoint(Point64( Round(FPathIn[0].X + X * FDelta),
            Round(FPathIn[0].Y + Y * FDelta)));
          if X < 0 then X := 1
          else if Y < 0 then Y := 1
          else X := -1;
        end;
      end;
      SetLength(FPathOut, FOutPos);
      FSolution[solCnt] := FPathOut;
      Inc(solCnt);
      Continue;
    end;

    //build normals ...
    SetLength(FNorms, pathLen);
    for j := 0 to pathLen-2 do
      FNorms[j] := GetUnitNormal(FPathIn[j], FPathIn[j+1]);
    if (node.FEndType in [etOpenJoined, etPolygon]) then
      FNorms[pathLen-1] := GetUnitNormal(FPathIn[pathLen-1], FPathIn[0]) else
      FNorms[pathLen-1] := FNorms[pathLen-2];

    //offset using normals ...
    if node.FEndType = etPolygon then
    begin
      k := pathLen -1;
      for j := 0 to pathLen-1 do
        OffsetPoint(j, k, node.FJoinType);
      SetLength(FPathOut, FOutPos);
      FSolution[solCnt] := FPathOut;
      Inc(solCnt);
    end
    else if (node.FEndType = etOpenJoined) then
    begin
      k := pathLen -1;
      for j := 0 to pathLen-1 do OffsetPoint(j, k, node.FJoinType);
      SetLength(FPathOut, FOutPos);
      FSolution[solCnt] := FPathOut;
      Inc(solCnt);

      FOutPos := 0;
      FPathOut := nil;

      //reverse normals and repeat offsetting ...
      norm := FNorms[pathLen - 1];
      for j := pathLen-1 downto 1 do
      begin
        FNorms[j].X := -FNorms[j-1].X;
        FNorms[j].Y := -FNorms[j-1].Y;
      end;
      FNorms[0].X := -norm.X;
      FNorms[0].Y := -norm.Y;

      k := 0;
      for j := pathLen-1 downto 0 do OffsetPoint(j, k, node.FJoinType);
      SetLength(FPathOut, FOutPos);

      FSolution[solCnt] := FPathOut;
      Inc(solCnt);
    end else
    begin
      //offset the open path going forward ...
      k := 0;
      for j := 1 to pathLen-2 do OffsetPoint(j, k, node.FJoinType);

      //handle the end (butt, round or square) ...
      if node.FEndType = etOpenButt then
      begin
        j := pathLen - 1;
        AddPoint(Point64(round(FPathIn[j].X + FNorms[j].X *FDelta),
          round(FPathIn[j].Y + FNorms[j].Y * FDelta)));
        AddPoint(Point64(round(FPathIn[j].X - FNorms[j].X *FDelta),
          round(FPathIn[j].Y - FNorms[j].Y * FDelta)));
      end else
      begin
        j := pathLen - 1;
        k := pathLen - 2;
        FNorms[j].X := -FNorms[j].X;
        FNorms[j].Y := -FNorms[j].Y;
        FSinA := 0;
        if node.FEndType = etOpenSquare then
          DoSquare(j, k) else
          DoRound(j, k);
      end;

      //reverse normals ...
      for j := pathLen-1 downto 1 do
      begin
        FNorms[j].X := -FNorms[j-1].X;
        FNorms[j].Y := -FNorms[j-1].Y;
      end;
      FNorms[0].X := -FNorms[1].X;
      FNorms[0].Y := -FNorms[1].Y;

      //repeat offset but now going backward ...
      k := pathLen -1;
      for j := pathLen -2 downto 1 do OffsetPoint(j, k, node.FJoinType);

      //finally handle the start (butt, round or square) ...
      if node.FEndType = etOpenButt then
      begin
        AddPoint(Point64(round(FPathIn[0].X - FNorms[0].X *FDelta),
          round(FPathIn[0].Y - FNorms[0].Y * FDelta)));
        AddPoint(Point64(round(FPathIn[0].X + FNorms[0].X *FDelta),
          round(FPathIn[0].Y + FNorms[0].Y * FDelta)));
      end else
      begin
        FSinA := 0;
        if node.FEndType = etOpenSquare then
          DoSquare(0, 1) else
          DoRound(0, 1);
      end;
      SetLength(FPathOut, FOutPos);
      FSolution[solCnt] := FPathOut;
      Inc(solCnt);
    end;
  end;
  SetLength(FSolution, solCnt);
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.Execute(out solution: TPaths; delta: Double);
var
  i, Len: Integer;
  outerPath: TPath;
  bounds: TRect64;
begin
  solution := nil;
  if FNodeList.Count = 0 then Exit;

  //if polygon orientations are reversed, then simply reverse the delta ...
  GetLowestPolygonIdx;
  if (FLowestIdx >= 0) and
    (Area(TPathNode(FNodeList[FLowestIdx]).FPath) < 0) then //todo don't use Area :)
      delta := - delta;

  DoOffset(delta);

  //clean up 'corners' ...
  with TClipper.Create do
  try
    AddPaths(FSolution, ptSubject);
    Execute(ctUnion, solution, ftPositive);
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.AddPoint(const pt: TPoint64);
const
  BuffLength = 32;
begin
  if FOutPos = length(FPathOut) then
    SetLength(FPathOut, FOutPos + BuffLength);
  if (FOutPos > 0) and PointsEqual(FPathOut[FOutPos-1], pt) then Exit;
  FPathOut[FOutPos] := pt;
  Inc(FOutPos);
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.DoSquare(j, k: Integer);
begin
  //Two vertices, one using the prior offset's (k) normal one the current (j).
  //Do a 'normal' offset (by delta) and then another by 'de-normaling' the
  //normal hence parallel to the direction of the respective edges.
  AddPoint(Point64(
    round(FPathIn[j].X + FDelta * (FNorms[k].X - FNorms[k].Y)),
    round(FPathIn[j].Y + FDelta * (FNorms[k].Y + FNorms[k].X))));
  AddPoint(Point64(
    round(FPathIn[j].X + FDelta * (FNorms[j].X + FNorms[j].Y)),
    round(FPathIn[j].Y + FDelta * (FNorms[j].Y - FNorms[j].X))));
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.DoMiter(j, k: Integer; cosAplus1: Double);
var
  q: Double;
begin
  //see offset_triginometry4.svg
  q := FDelta / cosAplus1; //0 < cosAplus1 <= 2
  AddPoint(Point64(round(FPathIn[j].X + (FNorms[k].X + FNorms[j].X)*q),
    round(FPathIn[j].Y + (FNorms[k].Y + FNorms[j].Y)*q)));
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.DoRound(j, k: Integer);
var
  i, steps: Integer;
  a, X, X2, Y: Double;
begin
  a := ArcTan2(FSinA, FNorms[k].X * FNorms[j].X + FNorms[k].Y * FNorms[j].Y);
  steps := Max(Round(FStepsPerRad * Abs(a)), 1);

  X := FNorms[k].X;
  Y := FNorms[k].Y;
  for i := 1 to steps do
  begin
    AddPoint(Point64(
      round(FPathIn[j].X + X * FDelta),
      round(FPathIn[j].Y + Y * FDelta)));
    X2 := X;
    X := X * FCos - FSin * Y;
    Y := X2 * FSin + Y * FCos;
  end;
  AddPoint(Point64(
    round(FPathIn[j].X + FNorms[j].X * FDelta),
    round(FPathIn[j].Y + FNorms[j].Y * FDelta)));
end;
//------------------------------------------------------------------------------

procedure TClipperOffset.OffsetPoint(j: Integer;
  var k: Integer; JoinType: TJoinType);
var
  cosA: Double;
begin
  //A: angle between adjoining paths on left side (left WRT winding direction).
  //A == 0 deg (or A == 360 deg): collinear edges heading in same direction
  //A == 180 deg: collinear edges heading in opposite directions (ie a 'spike')
  //sin(A) < 0: convex on left.
  //cos(A) > 0: angles on both left and right sides > 90 degrees

  //cross product ...
  FSinA := (FNorms[k].X * FNorms[j].Y - FNorms[j].X * FNorms[k].Y);
  if (Abs(FSinA * FDelta) < 1.0) then //angle is approaching 180 or 360 deg.
  begin
    //dot product ...
    cosA := (FNorms[k].X * FNorms[j].X + FNorms[j].Y * FNorms[k].Y );
    if (cosA > 0) then //given condition above the angle is approaching 360 deg.
    begin
      //with angles approaching 360 deg collinear (whether concave or convex),
      //offsetting with two or more vertices (that would be so close together)
      //occasionally causes tiny self-intersections due to rounding.
      //So we offset with just a single vertex here ...
      AddPoint(Point64(round(FPathIn[j].X + FNorms[k].X * FDelta),
        round(FPathIn[j].Y + FNorms[k].Y * FDelta)));
      Exit;
    end;
    //else angle must be approaching 180 deg.
  end
  else if (FSinA > 1.0) then FSinA := 1.0
  else if (FSinA < -1.0) then FSinA := -1.0;

  if FSinA * FDelta < 0 then //ie a concave offset
  begin
    AddPoint(Point64(round(FPathIn[j].X + FNorms[k].X * FDelta),
      round(FPathIn[j].Y + FNorms[k].Y * FDelta)));
    AddPoint(FPathIn[j]); //this improves clipping removal later
    AddPoint(Point64(round(FPathIn[j].X + FNorms[j].X * FDelta),
      round(FPathIn[j].Y + FNorms[j].Y * FDelta)));
  end
  else
  begin
    //convex offsets here ...
    case JoinType of
      jtMiter:
      begin
        cosA := (FNorms[j].X * FNorms[k].X + FNorms[j].Y * FNorms[k].Y);
        //see offset_triginometry3.svg
        if (1 + cosA < FMiterLim) then DoSquare(j, k)
        else DoMiter(j, k, 1 + cosA);
      end;
      jtSquare:
      begin
        cosA := (FNorms[k].X * FNorms[j].X + FNorms[j].Y * FNorms[k].Y );
        if cosA >= 0 then //angles >= 90 deg. don't need squaring
          DoMiter(j, k, 1 + cosA) else
          DoSquare(j, k);
      end;
      jtRound: DoRound(j, k);
    end;
  end;
  k := j;
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

function OffsetPaths(const paths: TPaths;
  delta: Double; jt: TJoinType; et: TEndType): TPaths;
begin
  with TClipperOffset.Create do
  try
    AddPaths(paths, jt, et);
    Execute(Result, delta);
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------

end.
