unit ClipperTriangulation;

(*******************************************************************************
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (beta)                                                     *
* Date      :  11 Noveber 2017                                                 *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
* Purpose   :  Triangulate clipping solutions                                  *
* License   :  http://www.boost.org/LICENSE_1_0.txt                            *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
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

{$IFDEF DEBUG}
  {$UNDEF INLINING}
{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Clipper;

type

  TOutRecTri = class;

  TOutPtTri = class(TOutPt)
    Outrec       : TOutRec;
    RightOutrec  : TOutRecTri;
  end;

  TOutRecTri = class(TOutRec)
    LeftOutPt    : TOutPtTri;
  end;

  TClipperTri = class(TClipper)
  private
    FLastOp      : TOutPt;
    FTriCount    : integer;
    FTriSolution : TPaths;
    function InsertPt(const pt: TPoint64; afterOutPt: TOutPt): TOutPtTri;
    procedure AddPolygon(const pt1, pt2, pt3: TPoint64);
    procedure Triangulate(outRec: TOutRec);
    procedure BuildResult(out triangles: TPaths);
  protected
    function CreateOutPt: TOutPt; override;
    function CreateOutRec: TOutRec; override;
    function AddOutPt(e: PActive; const pt: TPoint64): TOutPt; override;
    procedure AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64); override;
    procedure AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64); override;
  public
    function Execute(clipType: TClipType; out triangles: TPaths;
      fillRule: TFillRule = frEvenOdd): Boolean; override;
    //The following public methods in the base Clipper class are of no use with
    //Triangulation so they'll raise an exception if you try to use them.
    function Execute(clipType: TClipType; var polytree: TPolyTree;
      out openPaths: TPaths; fillRule: TFillRule = frEvenOdd): Boolean; override;
    function Execute(clipType: TClipType; out closedPaths, openPaths: TPaths;
      fillRule: TFillRule = frEvenOdd): Boolean; override;
  end;

implementation

resourcestring
  rsWrongExecuteMethod = 'TClipperTri: You''re calling the wrong Execute method';

{$OVERFLOWCHECKS OFF}

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

function CrossProductVal(const pt1, pt2, pt3: TPoint64; out val: Int64): Int64;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := ((pt2.x-pt1.x) * (pt1.y-pt3.y) - (pt1.x-pt3.x) * (pt2.y-pt1.y));
  val := result;
end;
//------------------------------------------------------------------------------

function IsHotEdge(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := assigned(e.OutRec) and assigned(e.OutRec.Pts);
end;
//------------------------------------------------------------------------------

function IsStartSide(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  //when this function returns true, the solution polygon is internal on the
  //right of this edge.
  Result := (e = e.OutRec.startE);
end;
//------------------------------------------------------------------------------

function GetOutPt(e: PActive): TOutPt; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if IsStartSide(e) then
    Result := e.OutRec.Pts else
    Result := e.OutRec.Pts.Next;
end;
//------------------------------------------------------------------------------

function GetLeftAdjacentHotEdge(e: PActive): PActive;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := e.PrevInAEL;
  while assigned(result) and not IsHotEdge(result) do result := result.PrevInAEL;
end;
//------------------------------------------------------------------------------

function GetRightAdjacentHotEdge(e: PActive): PActive;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := e.NextInAEL;
  while assigned(result) and not IsHotEdge(result) do result := result.NextInAEL;
end;
//------------------------------------------------------------------------------

procedure DisposeOutPt(pp: TOutPt);  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if assigned(pp.Prev) then pp.Prev.Next := pp.Next;
  if assigned(pp.Next) then pp.Next.Prev := pp.Prev;
  if assigned(TOutPtTri(pp).RightOutrec) then
    TOutPtTri(pp).RightOutrec.LeftOutPt := nil;
  pp.Free;
end;
//------------------------------------------------------------------------------

procedure UpdateHelper(rightOr: TOutRec; leftOp: TOutPt);
  {$IFDEF INLINING} inline; {$ENDIF}
var
  lftOpt: TOutPtTri;
  rightOrt: TOutRecTri;
begin
  lftOpt := TOutPtTri(leftOp);
  rightOrt := TOutRecTri(rightOr);
  if assigned(lftOpt) and assigned(lftOpt.RightOutrec) then
    lftOpt.RightOutrec.LeftOutPt := nil;
  if assigned(rightOrt.LeftOutPt) then
    TOutPtTri(rightOrt.LeftOutPt).RightOutrec := nil;
  rightOrt.LeftOutPt := lftOpt;
  if assigned(leftOp) then lftOpt.RightOutrec := rightOrt;
end;
//------------------------------------------------------------------------------

procedure Update(op: TOutPt; outRec: TOutRec);
var
  op2: TOutPt;
begin
  op2 := op;
  repeat
    if assigned(TOutPtTri(op2).RightOutrec) then
      UpdateHelper(TOutPtTri(op2).RightOutrec, nil);
    TOutPtTri(op2).Outrec := outRec;
    op2 := op2.Next;
  until (op2 = op);
end;

//------------------------------------------------------------------------------
// TClipperTri methods ...
//------------------------------------------------------------------------------

function TClipperTri.InsertPt(const pt: TPoint64; afterOutPt: TOutPt): TOutPtTri;
begin
  Result := TOutPtTri.Create;
  Result.Pt := pt;
  Result.Prev := afterOutPt;
  Result.Next := afterOutPt.Next;
  Result.Outrec := TOutPtTri(afterOutPt).Outrec;
  Result.RightOutrec := nil;
  afterOutPt.Next.Prev := Result;
  afterOutPt.Next := Result;
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddPolygon(const pt1, pt2, pt3: TPoint64);
var
  len: integer;
  path: TPath;
const
  buff_size = 128;
begin
  setLength(path, 3);
  path[0] := pt3; path[1] := pt2; path[2] := pt1;

  len := Length(FTriSolution);
  if FTriCount = len then
    setLength(FTriSolution, len + buff_size);
  FTriSolution[FTriCount] := path;
  inc(FTriCount);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.Triangulate(outRec: TOutRec);
var
  cpVal: Int64;
  op, op2, opEnd: TOutPt;
begin
  op := outRec.Pts;
  if op.Next = op.Prev then Exit;
  opEnd := op.Next;
  while true do
  begin
    op2 := op;
    while (op.Prev <> opEnd) do
    begin
      if CrossProductVal(op.Pt, op.Prev.Pt, op.Prev.Prev.Pt, cpVal) >= 0 then
        break;
      if op2 <> op then
      begin
        //Due to rounding, the clipping algorithm can occasionally produce
        //tiny self-intersections and these need removing ...
        if CrossProductVal(op2.Pt, op.Pt, op.Prev.Prev.Pt, cpVal) > 0 then
        begin
          if assigned(TOutPtTri(op).RightOutrec) then
            UpdateHelper(TOutPtTri(op).RightOutrec, op2);
          DisposeOutPt(op);
          op := op2;
          continue;
        end;
      end;
      op := op.Prev;
    end;

    if (op.Prev = opEnd) then break;
    if (cpVal <> 0) then
      AddPolygon(op.Pt, op.Prev.Pt, op.Prev.Prev.Pt);
    if assigned(TOutPtTri(op.Prev).RightOutrec) then
      UpdateHelper(TOutPtTri(op.Prev).RightOutrec, op);
    DisposeOutPt(op.Prev);
    if op <> outRec.Pts then op := op.Next;
  end;
end;
//------------------------------------------------------------------------------

function TClipperTri.CreateOutPt: TOutPt;
begin
  Result := TOutPtTri.Create;
  TOutPtTri(Result).Outrec := nil;
  TOutPtTri(Result).RightOutrec := nil;
end;
//------------------------------------------------------------------------------

function TClipperTri.CreateOutRec: TOutRec;
begin
  Result := TOutRecTri.Create;
  TOutRecTri(Result).LeftOutPt := nil;
end;
//------------------------------------------------------------------------------

function TClipperTri.AddOutPt(e: PActive; const pt: TPoint64): TOutPt;
var
  e2: PActive;
begin
  result := inherited;
  TOutPtTri(result).Outrec := e.OutRec;
  FLastOp := result;
  Triangulate(e.OutRec);
  if IsStartSide(e) and not assigned(TOutPtTri(Result).RightOutrec) then
  begin
    e2 := GetRightAdjacentHotEdge(e);
    if assigned(e2) then UpdateHelper(e2.OutRec, Result);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64);
var
  locMinOr, botOr: TOutRec;
  locMinLft, locMinRt, botLft, botRt, startOp, endOp: TOutPt;
  e: PActive;
begin
  inherited;
  locMinOr := e1.OutRec;
  TOutPtTri(locMinOr.Pts).Outrec := locMinOr;
  UpdateHelper(locMinOr, locMinOr.Pts);
  if (locMinOr.Flag = orOuter) then Exit;

  //do 'keyholing' ...
  e := GetRightAdjacentHotEdge(e1);
  if (e = e2) then e := GetRightAdjacentHotEdge(e2);
  if not assigned(e) then e := GetLeftAdjacentHotEdge(e1);
  botLft := TOutRecTri(e.OutRec).LeftOutPt;
  botRt := GetOutPt(e);

  if not assigned(botLft) or
    not assigned(TOutPtTri(botLft).Outrec.startE) or
    (botRt.Pt.Y < botLft.Pt.Y) then botLft := botRt;

  botRt := InsertPt(botLft.Pt, botLft.Prev);
  botOr := TOutPtTri(botLft).Outrec;
  if not assigned(botOr.Pts) then botOr := botOr.Owner;

  startOp := botOr.Pts;
  endOp := startOp.Next;

  locMinOr.Flag := orOuter;
  locMinOr.Owner := nil;
  locMinLft := locMinOr.Pts;
  locMinRt := InsertPt(locMinLft.Pt, locMinLft);

  //locMinOr will contain the polygon to the right of the join (ascending),
  //and botOr will contain the polygon to the left of the join (descending).

  //tail -> botRt -> locMinRt : locMinRt is joined by botRt tail
  locMinRt.Next := endOp;
  endOp.Prev := locMinRt;
  botRt.Next := locMinRt;
  locMinRt.Prev := botRt;
  locMinOr.Pts := locMinRt;

  //locMinLft -> botLft -> head : locMinLft joins behind botLft (left)
  startOp.Next := locMinLft;
  locMinLft.Prev := startOp;
  botLft.Prev := locMinLft;
  locMinLft.Next := botLft;
  TOutPtTri(locMinLft).Outrec := botOr; //ie abreviated update()

  Update(locMinRt, locMinOr); //updates the outrec for each op

  //exchange endE's ...
  e := botOr.endE;
  botOr.endE := locMinOr.endE;
  locMinOr.endE := e;
  botOr.endE.OutRec := botOr;
  locMinOr.endE.OutRec := locMinOr;

  //update helper info  ...
  UpdateHelper(locMinOr, locMinRt);
  UpdateHelper(botOr, botOr.Pts);
  Triangulate(locMinOr);
  Triangulate(botOr);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64);
var
  op: TOutPt;
  outrec: TOutRec;
  isOuter: Boolean;
  e: PActive;
begin
  outrec := e1.outrec;
  //very occasionally IsStartSide(e1) is wrong so ...
  isOuter := IsStartSide(e1) or (e1.OutRec = e2.OutRec);
  if isOuter then
  begin
    if TOutRecTri(e1.OutRec).LeftOutPt <> nil then
      UpdateHelper(e1.OutRec, nil);
    if TOutRecTri(e2.OutRec).LeftOutPt <> nil then
      UpdateHelper(e2.OutRec, nil);
  end;
  inherited;

  if not assigned(outRec.Pts) then outRec := outRec.Owner;
  if isOuter then
  begin
    op := outRec.Pts;
    if assigned(TOutPtTri(op).RightOutrec) then
      UpdateHelper(TOutPtTri(op).RightOutrec, nil)
    else if assigned(TOutPtTri(op.Next).RightOutrec) then
      UpdateHelper(TOutPtTri(op.Next).RightOutrec, nil);
  end else
  begin
    e := GetRightAdjacentHotEdge(e2);
    if assigned(e) then UpdateHelper(e.OutRec, FLastOp);
    Update(outrec.Pts, outRec);
  end;
  Triangulate(outrec);
end;
//------------------------------------------------------------------------------

function TClipperTri.Execute(clipType: TClipType; out triangles: TPaths;
  fillRule: TFillRule): Boolean;
begin
  triangles := nil;
  if clipType = ctNone then
    Result := true
  else
    try
      Result := ExecuteInternal(clipType, fillRule);
      if Result then BuildResult(triangles);
    finally
      CleanUp;
    end;
end;
//------------------------------------------------------------------------------

function TClipperTri.Execute(clipType: TClipType; var polytree: TPolyTree;
  out openPaths: TPaths; fillRule: TFillRule = frEvenOdd): Boolean;
begin
  raise EClipperLibException.Create(rsWrongExecuteMethod);
end;
//------------------------------------------------------------------------------

function TClipperTri.Execute(clipType: TClipType;
  out closedPaths, openPaths: TPaths; fillRule: TFillRule = frEvenOdd): Boolean;
begin
  raise EClipperLibException.Create(rsWrongExecuteMethod);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.BuildResult(out triangles: TPaths);
var
  i: Integer;
begin
  SetLength(triangles, FTriCount);
  for i := 0 to FTriCount -1 do
    triangles[i] := FTriSolution[i];
end;
//------------------------------------------------------------------------------

end.

