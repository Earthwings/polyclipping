unit Clipper2;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  20 January 2017                                                 *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************)

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

//use_int32: When enabled 32bit ints are used instead of 64bit ints. This
//improve performance but coordinate values are limited to the range +/- 46340
//{$DEFINE use_int32}

//use_xyz: adds a Z member to IntPoint (with only a minor cost to performance)
//{$DEFINE use_xyz}

//use_lines: Enables open path clipping (with a very minor cost to performance)
//{$DEFINE use_lines}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

{$IFDEF FPC}
  {$DEFINE INLINING}
  {$DEFINE UInt64Support}
{$ELSE}
  {$IF CompilerVersion >= 25.0}
    {$LEGACYIFEND ON} // enable LEGACYIFEND for Delphi XE4+
  {$IFEND}

  {$IFDEF ConditionalExpressions}
    {$IF CompilerVersion >= 15}
      {$DEFINE UInt64Support}   //Delphi7 does marginally supports UInt64.
    {$IFEND}
    {$IF CompilerVersion >= 18} //Delphi 2007
      //While Inlining has been supported since D2005, both D2005 and D2006
      //have an Inline codegen bug (QC41166) so ignore Inline until D2007.
      {$DEFINE INLINING}
    {$IFEND}
  {$ENDIF}
{$ENDIF}

interface

uses
   SysUtils, Types, Classes, Math;

type
{$IFDEF use_int32}
  {$IF CompilerVersion < 20}
    cInt = Integer;
  {$ELSE}
    cInt = Int32; //Int32 supported since D2009.
  {$IFEND}
{$ELSE}
  cInt = Int64;
{$ENDIF}

  PIntPoint = ^TIntPoint;
{$IFDEF use_xyz}
  TIntPoint = record X, Y, Z: cInt; end;
{$ELSE}
  TIntPoint = record X, Y: cInt; end;
{$ENDIF}

  TPath = array of TIntPoint;
  TPaths = array of TPath;

  TIntRect = record Left, Top, Right, Bottom: cInt; end;
  TDoublePoint = record X, Y: Double; end;
  TArrayOfDoublePoint = array of TDoublePoint;

{$IFDEF use_xyz}
  TZFillCallback =
    procedure (const E1Bot, E1Top, E2Bot, E2Top: TIntPoint; var Pt: TIntPoint);
{$ENDIF}

  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);

  //By far the most widely used winding rules for polygon filling are EvenOdd
  //and NonZero (see GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32).
  //https://www.w3.org/TR/SVG/painting.html
  TPolyFillType = (pftEvenOdd, pftNonZero, pftPositive, pftNegative);

  TVertexFlag = (vfOpen, vfStart, vfEnd, vfMaxima, vfMinima);
  TVertexFlags = set of TVertexFlag;

  PVertex = ^TVertex;
  TVertex = record
    Pt    : TIntPoint;
    next  : PVertex;
    prev  : PVertex;
    flags : TVertexFlags;
  end;

  PVertexArray = ^TVertexArray;
  TVertexArray = array[0..MaxInt div sizeof(TVertex) -1] of TVertex;

  //Every closed path (or polygon) is made up of a series of vertices forming
  //edges that alternate between going up (relative to the Y-axis) and then
  //going down. Edges that consecutively go up or consecutively go down can be
  //grouped together into 'bounds' (or sides if they're simple convex polygons).
  //Local Minima are pointers to those vertices where descending bounds become
  //ascending bounds.

  PLocalMinimum = ^TLocalMinimum;
  TLocalMinimum = record
    vertex    : PVertex;
    PolyType  : TPolyType;
    PolyIdx   : integer;   //not used by the clipping algorithm
    IsOpen    : Boolean;
  end;

  POutRec = ^TOutRec;

  TActiveFlag = (afOpen, afMaxima);
  TActiveFlags = set of TActiveFlag;

  PActive = ^TActive;
  TActive = record
    Bot      : TIntPoint;
    Curr     : TIntPoint;
    Top      : TIntPoint;
    Dx       : double;        //inverse of edge slope (zero = vertical)
    WindDelta: integer;       //wind direction (is zero for open paths)
    WindCnt  : integer;       //edge wind count of
    WindCnt2 : integer;       //wind count of opposite TPolyType
    OutRec   : POutRec;
    Flags    : TActiveFlags;

    //AEL - active edge list - edges participating in current scanbeam
    PrevInAEL: PActive;
    NextInAEL: PActive;
    //SEL - sorted edge list - new order of active edges at top of scambeam
    //(determines intersections and re-used for horizontal edges)
    PrevInSEL: PActive;       //DLL needed for EdgesAdjacent() method
    NextInSEL: PActive;
    vertTop  : PVertex;       //edge's top vertex
    LocMin   : PLocalMinimum; //bottom of bound
  end;

  PScanLine = ^TScanLine;
  TScanLine = record
    Y       : cInt;
    Next    : PScanLine;
  end;

  POutPt = ^TOutPt;
  TOutPt = record
    Pt       : TIntPoint;
    Next     : POutPt;
    Prev     : POutPt;
  end;

  //OutRec: contains a path in the clipping solution. Edges in the AEL will
  //carry a pointer to an OutRec when they are part of the clipping solution.
  TOutRec = record
    Idx         : Integer;
    IsOpen      : Boolean;
    Pts         : POutPt;
    LeftE       : PActive;
    RightE      : PActive;
  end;

  TDirection = (dRightToLeft, dLeftToRight);

  TClipper2 = class
  private
    FScanLine           : PScanLine;    //ScanLine list
    FLocMinListSorted   : Boolean;
    FUse64BitRange      : Boolean;      //see LoRange and HiRange consts notes below
    FHasOpenPaths       : Boolean;
    FCurrentLocMinIdx   : integer;

    FIntersectList      : TList;
    FClipType           : TClipType;
    FFillType           : TPolyFillType;
    FExecuteLocked      : Boolean;
    procedure RangeCheck(const pt: TIntPoint);
    function PathToVertexArray(const p: TPath;
      polyType: TPolyType; isOpen: Boolean): PVertexArray;
    procedure InsertScanLine(const Y: cInt);
    function PopScanLine(out Y: cInt): Boolean;
    function PopLocalMinima(Y: cInt;
      out LocalMinima: PLocalMinimum): Boolean;
    procedure DisposeScanLineList;
    procedure DisposeLocalMinimaList;
    procedure DisposePolyPts(PP: POutPt);
    procedure StartOutRec(e1, e2: PActive; const pt: TIntPoint);
    procedure DisposeOutRec(Index: Integer);
    procedure DisposeAllOutRecs;
    function IsContributing(Edge: PActive): Boolean;
    procedure SetWindingCount(Edge: PActive);
    procedure InsertLocalMinimaIntoAEL(const BotY: cInt);
    procedure DeleteFromAEL(E: PActive);
    procedure AddOutPt(e: PActive; const pt: TIntPoint);
    procedure AddLocalMinPoly(E1, E2: PActive; const Pt: TIntPoint);
    procedure AddLocalMaxPoly(E1, E2: PActive; const Pt: TIntPoint);
    procedure AddEdgeToSEL(Edge: PActive);
    function PopEdgeFromSEL(out E: PActive): Boolean;
    procedure CopyAELToSEL;
    procedure UpdateEdgeIntoAEL(var E: PActive);
    procedure SwapOutRecs(E1, E2: PActive);
    procedure IntersectEdges(E1,E2: PActive; Pt: TIntPoint);
    procedure ProcessIntersections(const TopY: cInt);
    procedure DisposeIntersectNodes;
    procedure BuildIntersectList(const TopY: cInt);
    procedure ProcessIntersectList;
    function FixupIntersectionOrder: Boolean;
    procedure SwapPositionsInAEL(E1, E2: PActive);
    procedure SwapPositionsInSEL(E1, E2: PActive);
    procedure ProcessHorizontals(Y: cInt);
    procedure ProcessHorizontal(HorzEdge: PActive);
    procedure DoTopOfScanbeam(Y: cInt);
    function DoMaxima(e: PActive): PActive;
    procedure AppendPath(E1, E2: PActive);
    function BuildResult: TPaths;
  protected
    FPolyOutList      : TList;
    FLocMinList       : TList;
    FActiveEdges      : PActive;      //active edge list (AEL)
    FSortedEdges      : PActive;      //used for temporary sorting
    FPathCount        : integer;
    FVertexList       : TList;
    procedure Reset; virtual;
  public
     constructor Create; virtual;
    destructor Destroy; override;
    procedure Clear; virtual;
    function GetBounds: TIntRect;
    procedure AddPath(const path: TPath; polyType: TPolyType = ptSubject;
      isOpen: Boolean = false); virtual;
    procedure AddPaths(const paths: TPaths; polyType: TPolyType = ptSubject;
      isOpen: Boolean = false); virtual;
    function Execute(clipType: TClipType; out solution: TPaths;
      fillType: TPolyFillType = pftEvenOdd): Boolean;
  end;

  EClipperLibException = class(Exception);

function Orientation(const path: TPath): Boolean; overload;
function Area(const path: TPath): Double; overload;
function PointInPolygon (const pt: TIntPoint; const poly: TPath): Integer; overload;
function GetBounds(const paths: TPaths): TIntRect;

{$IFDEF use_xyz}
function IntPoint(const X, Y: Int64; Z: Int64 = 0): TIntPoint; overload;
function IntPoint(const X, Y: Double; Z: Double = 0): TIntPoint; overload;
{$ELSE}
function IntPoint(const X, Y: cInt): TIntPoint; overload;
function IntPoint(const X, Y: Double): TIntPoint; overload;
{$ENDIF}

function DoublePoint(const X, Y: Double): TDoublePoint; overload;
function DoublePoint(const Ip: TIntPoint): TDoublePoint; overload;

function ReversePath(const path: TPath): TPath;
function ReversePaths(const paths: TPaths): TPaths;

const
  EmptyRect: TIntRect = (Left: 0; Top: 0; Right: 0; Bottom: 0);

implementation

 const
//The math performed in the SlopesEqual function places the most constraints
//on coordinate values. To avoid overflow errors there, coordinate values must
//not exceed HiRange below. Also, when coordinate values exceed LoRange,
//the Int128 math required will render the library approx. 10-15% slower.
{$IFDEF use_int32}
  LoRange: cInt = 46340;
  HiRange: cInt = 46340;              //32bit math  (coord range +/-4.6e+4)
{$ELSE}
  LoRange: cInt = $B504F333;          //64bit math  (coord range +/- 3.0e+9)
  HiRange: cInt = $3FFFFFFFFFFFFFFF;  //128bit math (coord range +/- 9.2e+18)
{$ENDIF}

{$OVERFLOWCHECKS OFF}
//This is a necessary workaround for a Delphi compiler bug that very
//occasionally reports overflow errors while still returning correct values
//eg var A, B: Int64; begin A := -$13456780; B := -$73456789; A := A * B; end;
//see https://forums.embarcadero.com/message.jspa?messageID=871444

  HORIZONTAL = NegInfinity;
  UNASSIGNED  : integer = -1;

type
  PIntersectNode = ^TIntersectNode;
  TIntersectNode = record
    Edge1  : PActive;
    Edge2  : PActive;
    Pt     : TIntPoint;
  end;

resourcestring
  rsDivZeroErr   = 'Int128 divide by zero error';
  rsRangeErr     = 'Coordinate exceeds range bounds';
  rsOpenPathErr  = 'TPolyTree struct is needed for open path clipping.';
  rsClippingErr  = 'Undefined clipping error';

function IsLeftSide(Edge: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if (Edge = Edge.OutRec.LeftE) then
    result := true else
    result := false;
end;
//------------------------------------------------------------------------------

function TopX(Edge: PActive; const currentY: cInt): cInt; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if currentY = Edge.Top.Y then Result := Edge.Top.X
  else if Edge.Top.X = Edge.Bot.X then Result := Edge.Bot.X
  else Result := Edge.Bot.X + Round(Edge.Dx*(currentY - Edge.Bot.Y));
end;
//------------------------------------------------------------------------------

function IsHorizontal(Edge: PActive): boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := Edge.Dx = HORIZONTAL;
end;
//------------------------------------------------------------------------------

function IsOpen(Edge: PActive): boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := afOpen in Edge.Flags;
end;
//------------------------------------------------------------------------------

function TClipper2.GetBounds: TIntRect;
var
  i: integer;
  v, vStart: PVertex;
begin
  if FVertexList.Count > 0 then
  begin
    with PVertex(FVertexList[0]).Pt do
    begin
      result.Left := X;
      result.Top := Y;
      result.Right := X;
      result.Bottom := Y;
    end;
    for i := 0 to FVertexList.Count -1 do
    begin
      vStart := FVertexList[i];
      v := vStart;
      repeat
        v := v.next;
        if v.Pt.X < result.Left then result.Left := v.Pt.X
        else if v.Pt.X > result.Right then result.Right := v.Pt.X;
        if v.Pt.Y < result.Top then result.Top := v.Pt.Y
        else if v.Pt.Y > result.Bottom then result.Bottom := v.Pt.Y;
      until v = vStart;
    end;
  end
  else result := EmptyRect;
end;
//------------------------------------------------------------------------------

{$IFNDEF use_int32}

//------------------------------------------------------------------------------
// UInt64 math support for Delphi 6
//------------------------------------------------------------------------------

{$IFNDEF UInt64Support}
function CompareUInt64(const i, j: Int64): Integer;
begin
  if Int64Rec(i).Hi < Int64Rec(j).Hi then
    Result := -1
  else if Int64Rec(i).Hi > Int64Rec(j).Hi then
    Result := 1
  else if Int64Rec(i).Lo < Int64Rec(j).Lo then
    Result := -1
  else if Int64Rec(i).Lo > Int64Rec(j).Lo then
    Result := 1
  else
    Result := 0;
end;
{$ENDIF}

function UInt64LT(const i, j: Int64): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
{$IFDEF UInt64Support}
  Result := UInt64(i) < UInt64(j);
{$ELSE}
  Result := CompareUInt64(i, j) = -1;
{$ENDIF}
end;

//------------------------------------------------------------------------------
// Int128 Functions ...
//------------------------------------------------------------------------------

const
  Mask32Bits = $FFFFFFFF;

type
  //nb: TInt128.Lo is typed Int64 instead of UInt64 to provide Delphi 7
  //compatability. However while UInt64 isn't a recognised type in
  //Delphi 7, it can still be used in typecasts.
  TInt128 = record
    Hi   : Int64;
    Lo   : Int64;
  end;

procedure Int128Negate(var Val: TInt128);
begin
  if Val.Lo = 0 then
  begin
    Val.Hi := -Val.Hi;
  end else
  begin
    Val.Lo := -Val.Lo;
    Val.Hi := not Val.Hi;
  end;
end;
//------------------------------------------------------------------------------

function Int128(const val: Int64): TInt128; overload;
begin
  Result.Lo := val;
  if val < 0 then
    Result.Hi := -1 else
    Result.Hi := 0;
end;
//------------------------------------------------------------------------------

function Int128Equal(const Int1, Int2: TInt128): Boolean;
begin
  Result := (Int1.Lo = Int2.Lo) and (Int1.Hi = Int2.Hi);
end;
//------------------------------------------------------------------------------

function Int128Mul(Int1, Int2: Int64): TInt128;
var
  A, B, C: Int64;
  Int1Hi, Int1Lo, Int2Hi, Int2Lo: Int64;
  Negate: Boolean;
begin
  //save the Result's sign before clearing both sign bits ...
  Negate := (Int1 < 0) <> (Int2 < 0);
  if Int1 < 0 then Int1 := -Int1;
  if Int2 < 0 then Int2 := -Int2;

  Int1Hi := Int1 shr 32;
  Int1Lo := Int1 and Mask32Bits;
  Int2Hi := Int2 shr 32;
  Int2Lo := Int2 and Mask32Bits;

  A := Int1Hi * Int2Hi;
  B := Int1Lo * Int2Lo;
  //because the high (sign) bits in both int1Hi & int2Hi have been zeroed,
  //there's no risk of 64 bit overflow in the following assignment
  //(ie: $7FFFFFFF*$FFFFFFFF + $7FFFFFFF*$FFFFFFFF < 64bits)
  C := Int1Hi*Int2Lo + Int2Hi*Int1Lo;
  //Result = A shl 64 + C shl 32 + B ...
  Result.Hi := A + (C shr 32);
  A := C shl 32;

  Result.Lo := A + B;
  if UInt64LT(Result.Lo, A) then
    Inc(Result.Hi);

  if Negate then Int128Negate(Result);
end;
//------------------------------------------------------------------------------

{$ENDIF} //$IFNDEF use_int32

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

function PointsEqual(const P1, P2: TIntPoint): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (P1.X = P2.X) and (P1.Y = P2.Y);
end;
//------------------------------------------------------------------------------

{$IFDEF use_xyz}
function IntPoint(const X, Y: Int64; Z: Int64 = 0): TIntPoint;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;
//------------------------------------------------------------------------------

function IntPoint(const X, Y: Double; Z: Double = 0): TIntPoint;
begin
  Result.X := Round(X);
  Result.Y := Round(Y);
  Result.Z := Round(Z);
end;
//------------------------------------------------------------------------------

{$ELSE}

function IntPoint(const X, Y: cInt): TIntPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function IntPoint(const X, Y: Double): TIntPoint;
begin
  Result.X := Round(X);
  Result.Y := Round(Y);
end;

{$ENDIF}
//------------------------------------------------------------------------------

function DoublePoint(const X, Y: Double): TDoublePoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function DoublePoint(const Ip: TIntPoint): TDoublePoint;
begin
  Result.X := Ip.X;
  Result.Y := Ip.Y;
end;
//------------------------------------------------------------------------------

function Area(const path: TPath): Double;
var
  I, J, Cnt: Integer;
  D: Double;
begin
  Result := 0.0;
  Cnt := Length(path);
  if (Cnt < 3) then Exit;
  J := cnt - 1;
  for I := 0 to Cnt -1 do
  begin
    D := (path[j].X + path[i].X);
    Result := Result + D * (path[j].Y - path[i].Y);
    J := I;
  end;
  Result := -Result * 0.5;
end;
//------------------------------------------------------------------------------

function Area(Op: POutPt): Double; overload;
var
  op2: POutPt;
  d2: Double;
begin
  Result := 0;
  op2 := op;
  if Assigned(op2) then
    repeat
      d2 := op2.Prev.Pt.X + op2.Pt.X;
      Result := Result + d2 * (op2.Prev.Pt.Y - op2.Pt.Y);
      op2 := op2.Next;
    until op2 = op;
  Result := Result * 0.5;
end;
//------------------------------------------------------------------------------

function Area(OutRec: POutRec): Double; overload;
begin
  result := Area(OutRec.Pts);
end;
//------------------------------------------------------------------------------

function Orientation(const path: TPath): Boolean;
begin
  Result := Area(path) >= 0;
end;
//------------------------------------------------------------------------------

function ReversePath(const path: TPath): TPath;
var
  I, HighI: Integer;
begin
  HighI := high(path);
  SetLength(Result, HighI +1);
  for I := 0 to HighI do
    Result[I] := path[HighI - I];
end;
//------------------------------------------------------------------------------

function ReversePaths(const paths: TPaths): TPaths;
var
  I, J, highJ: Integer;
begin
  I := length(paths);
  SetLength(Result, I);
  for I := 0 to I -1 do
  begin
    highJ := high(paths[I]);
    SetLength(Result[I], highJ+1);
    for J := 0 to highJ do
      Result[I][J] := paths[I][highJ - J];
  end;
end;
//------------------------------------------------------------------------------

function GetBounds(const paths: TPaths): TIntRect;
var
  I,J,Len: Integer;
begin
  Len := Length(paths);
  I := 0;
  while (I < Len) and (Length(paths[I]) = 0) do inc(I);
  if (I = Len) then
  begin
    with Result do begin Left := 0; Top := 0; Right := 0; Bottom := 0; end;
    Exit;
  end;
  Result.Left := paths[I][0].X;
  Result.Right := Result.Left;
  Result.Top := paths[I][0].Y;
  Result.Bottom := Result.Top;
  for I := I to Len -1 do
    for J := 0 to High(paths[I]) do
    begin
      if paths[I][J].X < Result.Left then Result.Left := paths[I][J].X
      else if paths[I][J].X > Result.Right then Result.Right := paths[I][J].X;
      if paths[I][J].Y < Result.Top then Result.Top := paths[I][J].Y
      else if paths[I][J].Y > Result.Bottom then Result.Bottom := paths[I][J].Y;
    end;
end;
//------------------------------------------------------------------------------

function PointInPolygon (const pt: TIntPoint; const poly: TPath): Integer;
var
  i, cnt: Integer;
  d, d2, d3: double; //use cInt ???
  ip, ipNext: TIntPoint;
begin
  //returns 0 if false, +1 if true, -1 if pt ON polygon boundary
  //http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.88.5498&rep=rep1&type=pdf
  //nb: if poly bounds are known, test them first before calling this function.
  result := 0;
  cnt := Length(poly);
  if cnt < 3 then Exit;
  ip := poly[0];
  for i := 1 to cnt do
  begin
    if i < cnt then ipNext := poly[i]
    else ipNext := poly[0];

    if (ipNext.Y = pt.Y) then
    begin
      if (ipNext.X = pt.X) or ((ip.Y = pt.Y) and
        ((ipNext.X > pt.X) = (ip.X < pt.X))) then
      begin
        result := -1;
        Exit;
      end;
    end;

    if ((ip.Y < pt.Y) <> (ipNext.Y < pt.Y)) then
    begin
      if (ip.X >= pt.X) then
      begin
        if (ipNext.X > pt.X) then
          result := 1 - result
        else
        begin
          d2 := (ip.X - pt.X);
          d3 := (ipNext.X - pt.X);
          d := d2 * (ipNext.Y - pt.Y) - d3 * (ip.Y - pt.Y);
          if (d = 0) then begin result := -1; Exit; end;
          if ((d > 0) = (ipNext.Y > ip.Y)) then
            result := 1 - result;
        end;
      end else
      begin
        if (ipNext.X > pt.X) then
        begin
          d2 := (ip.X - pt.X);
          d3 := (ipNext.X - pt.X);
          d := d2 * (ipNext.Y - pt.Y) - d3 * (ip.Y - pt.Y);
          if (d = 0) then begin result := -1; Exit; end;
          if ((d > 0) = (ipNext.Y > ip.Y)) then
            result := 1 - result;
        end;
      end;
    end;
    ip := ipNext;
  end;
end;
//---------------------------------------------------------------------------

//See "The Point in Polygon Problem for Arbitrary Polygons" by Hormann & Agathos
//http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.88.5498&rep=rep1&type=pdf
function PointInPolygon (const pt: TIntPoint; ops: POutPt): Integer; overload;
var
  d, d2, d3: double; //nb: double not cInt avoids potential overflow errors
  opStart: POutPt;
  pt1, ptN: TIntPoint;
begin
  //returns 0 if false, +1 if true, -1 if pt ON polygon boundary
  result := 0;
  opStart := ops;
  pt1.X := ops.Pt.X; pt1.Y := ops.Pt.Y;
  repeat
    ops := ops.Next;
    ptN.X := ops.Pt.X; ptN.Y := ops.Pt.Y;

    if (ptN.Y = pt.Y) then
    begin
      if (ptN.X = pt.X) or ((pt1.Y = pt.Y) and
        ((ptN.X > pt.X) = (pt1.X < pt.X))) then
      begin
        result := -1;
        Exit;
      end;
    end;

    if ((pt1.Y < pt.Y) <> (ptN.Y < pt.Y)) then
    begin
      if (pt1.X >= pt.X) then
      begin
        if (ptN.X > pt.X) then
          result := 1 - result
        else
        begin
          d2 := (pt1.X - pt.X);
          d3 := (ptN.X - pt.X);
          d := d2 * (ptN.Y - pt.Y) - d3 * (pt1.Y - pt.Y);
          if (d = 0) then begin result := -1; Exit; end;
          if ((d > 0) = (ptN.Y > pt1.Y)) then
            result := 1 - result;
        end;
      end else
      begin
        if (ptN.X > pt.X) then
        begin
          d2 := (pt1.X - pt.X);
          d3 := (ptN.X - pt.X);
          d := d2 * (ptN.Y - pt.Y) - d3 * (pt1.Y - pt.Y);
          if (d = 0) then begin result := -1; Exit; end;
          if ((d > 0) = (ptN.Y > pt1.Y)) then
            result := 1 - result;
        end;
      end;
    end;
    pt1 := ptN;
  until ops = opStart;
end;
//---------------------------------------------------------------------------

function GetTopDeltaX(E1, E2: PActive): cInt; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if E1.Top.Y > E2.Top.Y then
    result := TopX(E2, E1.Top.Y) - E1.Top.X else
    result := E2.Top.X - TopX(E1, E2.Top.Y);
  end;
//------------------------------------------------------------------------------

function IsSamePolyType(const E1, E2: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := E1.LocMin.PolyType = E2.LocMin.PolyType;
end;
//------------------------------------------------------------------------------

function GetIntersectPoint(E1, E2: PActive): TIntPoint;
var
  B1,B2,M: Double;
begin
{$IFDEF use_xyz}
  ip.Z := 0;
{$ENDIF}

  //if parallel then return the current pt of E1 ...
  if (E1.Dx = E2.Dx) then
  begin
    result.Y := E1.Curr.Y;
    result.X := TopX(E1, result.Y);
    Exit;
  end
  else if E1.Dx = 0 then
  begin
    result.X := E1.Bot.X;
    if IsHorizontal(E2) then
      result.Y := E2.Bot.Y
    else
    begin
      with E2^ do B2 := Bot.Y - (Bot.X/Dx);
      result.Y := round(result.X/E2.Dx + B2);
    end;
  end
  else if E2.Dx = 0 then
  begin
    result.X := E2.Bot.X;
    if IsHorizontal(E1) then
      result.Y := E1.Bot.Y
    else
    begin
      with E1^ do B1 := Bot.Y - (Bot.X/Dx);
      result.Y := round(result.X/E1.Dx + B1);
    end;
  end else
  begin
    with E1^ do B1 := Bot.X - Bot.Y * Dx;
    with E2^ do B2 := Bot.X - Bot.Y * Dx;
    M := (B2-B1)/(E1.Dx - E2.Dx);
    result.Y := round(M);
    if Abs(E1.Dx) < Abs(E2.Dx) then
      result.X := round(E1.Dx * M + B1) else
      result.X := round(E2.Dx * M + B2);
  end;

  //The precondition - E.Curr.X > eNext.Curr.X - indicates that the two edges
  //do intersect below TopY (and hence below the tops of either Edge). However,
  //when edges are almost parallel, rounding errors may cause False positives -
  //indicating intersections when there really aren't any. Also, floating point
  //imprecision can incorrectly place an intersect point beyond/above an Edge.
  //Therfore, further adjustment to the intersect point may be warranted ...
  if (result.Y < E1.Top.Y) or (result.Y < E2.Top.Y) then
  begin
    //Find the lower top of the two edges and compare X's at this Y.
    //If Edge1's X is greater than Edge2's X then it's fair to assume an
    //intersection really has occurred...
    if (E1.Top.Y > E2.Top.Y) then
      result.Y := E1.Top.Y else
      result.Y := E2.Top.Y;
    if Abs(E1.Dx) < Abs(E2.Dx) then
      result.X := TopX(E1, result.Y) else
      result.X := TopX(E2, result.Y);
  end
  //finally, make sure the intersect point isn't BELOW the scanbeam ...
  else if (result.Y > E1.Curr.Y) then
  begin
    result.Y := E1.Curr.Y;
    if (abs(E1.Dx) > abs(E2.Dx)) then //ie use more vertical edge
      result.X := TopX(E2, result.Y) else
      result.X := TopX(E1, result.Y);
  end;
end;
//------------------------------------------------------------------------------

function SlopesEqual(E1, E2: PActive;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
{$IFNDEF use_int32}
  if UseFullInt64Range then
    Result := Int128Equal(Int128Mul(E1.Top.Y-E1.Bot.Y, E2.Top.X-E2.Bot.X),
      Int128Mul(E1.Top.X-E1.Bot.X, E2.Top.Y-E2.Bot.Y))
  else
{$ENDIF}
    Result := (E1.Top.Y-E1.Bot.Y) * (E2.Top.X-E2.Bot.X) =
      (E1.Top.X-E1.Bot.X) * (E2.Top.Y-E2.Bot.Y);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const Pt1, Pt2, Pt3: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
{$IFNDEF use_int32}
  if UseFullInt64Range then
    Result := Int128Equal(
      Int128Mul(Pt1.Y-Pt2.Y, Pt2.X-Pt3.X), Int128Mul(Pt1.X-Pt2.X, Pt2.Y-Pt3.Y))
  else
{$ENDIF}
    Result := (Pt1.Y-Pt2.Y)*(Pt2.X-Pt3.X) = (Pt1.X-Pt2.X)*(Pt2.Y-Pt3.Y);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const L1a, L1b, L2a, L2b: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
{$IFNDEF use_int32}
  if UseFullInt64Range then
    Result := Int128Equal(
      Int128Mul(L1a.Y-L1b.Y, L2a.X-L2b.X), Int128Mul(L2a.Y-L2b.Y, L1a.X-L1b.X))
  else
{$ENDIF}
  //dy1 * dx2 = dy2 * dx1
  Result := (L1a.Y-L1b.Y)*(L2a.X-L2b.X) = (L2a.Y-L2b.Y)*(L1a.X-L1b.X);
end;
//------------------------------------------------------------------------------

(*******************************************************************************
*  Dx:                             0(90º)                                      *
*                                  |                                           *
*                 +inf (180º) <--- o ---> -inf (0º)                            *
*******************************************************************************)
procedure SetDx(edge: PActive);
var
  dy: cInt;
begin
  dy := (edge.Top.Y - edge.Bot.Y);
  if dy = 0 then edge.dx := HORIZONTAL
  else edge.Dx := (edge.Top.X - edge.Bot.X)/dy;
end;
//------------------------------------------------------------------------------

function NextVertex(v: PVertex; goForward: boolean): PVertex; overload; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if goForward then
    result := v.next else
    result := v.prev;
end;
//------------------------------------------------------------------------------

function NextVertex(e: PActive): PVertex; overload; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if e.WindDelta > 0 then
    result := e.vertTop.next else
    result := e.vertTop.prev;
end;
//------------------------------------------------------------------------------

procedure SetMaximaFlag(Edge: PActive); {$IFDEF INLINING} inline; {$ENDIF}
begin
  include(Edge.Flags, afMaxima);
end;
//------------------------------------------------------------------------------

function IsMaximaFlagged(Edge: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := afMaxima in Edge.Flags;
end;
//------------------------------------------------------------------------------

function GetMaximaPair(E: PActive): PActive;
begin
  if IsHorizontal(E) then
  begin
    //we can't be sure whether the MaximaPair is on the left or right, so ...
    result := E.PrevInAEL;
    while assigned(Result) and (Result.Curr.X >= E.Top.X) do
    begin
      if Result.vertTop = E.vertTop then Exit;  //Found!
      result := result.PrevInAEL;
    end;
    result := E.NextInAEL;
    while assigned(Result) and (TopX(Result, E.Top.Y) <= E.Top.X) do
    begin
      if Result.vertTop = E.vertTop then Exit;  //Found!
      result := result.NextInAEL;
    end;
  end else
  begin
    result := E.NextInAEL;
    while assigned(Result) and (TopX(Result, E.Top.Y) <= E.Top.X) do
    begin
      if Result.vertTop = E.vertTop then Exit;  //Found!
      result := result.NextInAEL;
    end;
    result := nil; //this happens when the maxPair is a horizontal
  end;
end;

//------------------------------------------------------------------------------
// TClipper2 methods ...
//------------------------------------------------------------------------------

constructor TClipper2.Create;
begin
   FLocMinList := TList.Create;
  FPolyOutList := TList.Create;
  FIntersectList := TList.Create;
  FVertexList := TList.Create;
  Clear;
end;
//------------------------------------------------------------------------------

destructor TClipper2.Destroy;
begin
  Clear;
  FLocMinList.Free;
  FPolyOutList.Free;
  FIntersectList.Free;
  FVertexList.Free;
   inherited;
end;
//------------------------------------------------------------------------------

procedure TClipper2.Clear;
begin
  DisposeLocalMinimaList;
  FCurrentLocMinIdx := 0;
  FPathCount := 0;
  FLocMinListSorted := false;
  FUse64BitRange := False;
  FHasOpenPaths := False;
end;
//------------------------------------------------------------------------------

function LocMinListSort(item1, item2: Pointer): Integer;
var
  dy: cInt;
begin
  dy := PLocalMinimum(item2).vertex.Pt.Y - PLocalMinimum(item1).vertex.Pt.Y;
  if dy < 0 then result := -1
  else if dy > 0 then result := 1
  else result := 0;
end;
//------------------------------------------------------------------------------

 procedure TClipper2.Reset;
var
  i: integer;
 begin
  if not FLocMinListSorted then
    FLocMinList.Sort(LocMinListSort);
  for i := 0 to FLocMinList.Count -1 do
    InsertScanLine(PLocalMinimum(FLocMinList[i]).vertex.Pt.Y);
  FCurrentLocMinIdx := 0;
 end;
//------------------------------------------------------------------------------

procedure TClipper2.InsertScanLine(const Y: cInt);
var
  newSl, sl: PScanLine;
begin
  //single-linked list: sorted descending, ignoring dups.
  new(newSl);
  newSl.Y := Y;
  if not Assigned(FScanLine) then
  begin
    FScanLine := newSl;
    newSl.Next := nil;
  end else if Y > FScanLine.Y then
  begin
    newSl.Next := FScanLine;
    FScanLine := newSl;
  end else
  begin
    sl := FScanLine;
    while Assigned(sl.Next) and (Y <= sl.Next.Y) do sl := sl.Next;
    if Y <> sl.Y then
    begin
      newSl.Next := sl.Next;
      sl.Next := newSl;
    end
    else dispose(newSl);
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.PopScanLine(out Y: cInt): Boolean;
var
  sl: PScanLine;
begin
  Result := assigned(FScanLine);
  if not result then exit;
  Y := FScanLine.Y;
  sl := FScanLine;
  FScanLine := FScanLine.Next;
  dispose(sl);
end;
//------------------------------------------------------------------------------

function TClipper2.PopLocalMinima(Y: cInt;
  out LocalMinima: PLocalMinimum): Boolean;
begin
  Result := false;
  if FCurrentLocMinIdx = FLocMinList.Count then exit;
  LocalMinima := PLocalMinimum(FLocMinList[FCurrentLocMinIdx]);
  if (LocalMinima.vertex.Pt.Y = Y) then
  begin
    inc(FCurrentLocMinIdx);
    Result := true;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeScanLineList;
var
  sl: PScanLine;
begin
  while Assigned(FScanLine) do
  begin
    sl := FScanLine.Next;
    Dispose(FScanLine);
    FScanLine := sl;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposePolyPts(PP: POutPt);
var
  TmpPp: POutPt;
begin
  PP.Prev.Next := nil;
  while Assigned(PP) do
  begin
    TmpPp := PP;
    PP := PP.Next;
    dispose(TmpPp);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeOutRec(Index: Integer);
var
  OutRec: POutRec;
begin
  OutRec := FPolyOutList[Index];
  if Assigned(OutRec.Pts) then DisposePolyPts(OutRec.Pts);
  Dispose(OutRec);
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeAllOutRecs;
var
  I: Integer;
begin
  for I := 0 to FPolyOutList.Count -1 do DisposeOutRec(I);
  FPolyOutList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeLocalMinimaList;
var
  i: Integer;
begin
  for i := 0 to FLocMinList.Count -1 do
    Dispose(PLocalMinimum(FLocMinList[i]));
  FLocMinList.Clear;
  for i := 0 to FVertexList.Count -1 do FreeMem(FVertexList[i]);
  FVertexList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper2.RangeCheck(const pt: TIntPoint);
begin
  if FUse64BitRange then
  begin
    if (pt.X > HiRange) or (pt.Y > HiRange) or
      (-pt.X > HiRange) or (-pt.Y > HiRange) then
        raise EClipperLibException.Create(rsRangeErr);
  end
  else if (pt.X > LoRange) or (pt.Y > LoRange) or
    (-pt.X > LoRange) or (-pt.Y > LoRange) then
  begin
    FUse64BitRange := true;
    RangeCheck(pt);
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.PathToVertexArray(const p: TPath;
  polyType: TPolyType; isOpen: Boolean): PVertexArray;
var
  i, j, pathLen: integer;
  isFlat, goingUp, P0IsMinima, P0IsMaxima: boolean;
  v: PVertex;

  procedure AddLocMin(vert: PVertex);
  var
    lm: PLocalMinimum;
  begin
    if vfMinima in vert.flags then Exit; //ensures vertex is added only once
    Include(vert.flags, vfMinima);
    new(lm);
    lm.vertex := vert;
    lm.PolyType := polyType;
    lm.IsOpen := isOpen;
    lm.PolyIdx := FPathCount;
    FLocMinList.Add(lm);                 //nb: sorted in Reset()
  end;
  //----------------------------------------------------------------------------

begin
  result := nil;
  pathLen := length(p);
  while (pathLen > 1) and PointsEqual(p[pathLen -1], p[0]) do dec(pathLen);
  if (pathLen < 2) then Exit;
  RangeCheck(p[0]);

  P0IsMinima := false;
  P0IsMaxima := false;
  i := 1;
  //find the first non-horizontal segment in the path ...
  while (i < pathLen) and (p[i].Y = p[0].Y) do inc(i);
  isFlat := i = pathLen;
  if isFlat then
  begin
    if not isOpen then Exit;    //Ignore closed paths that have ZERO area.
    goingUp := false;           //And this just stops a compiler warning.
  end else
  begin
    goingUp := p[i].Y < p[0].Y; //because I'm using an inverted Y-axis display
    if goingUp then
    begin
      i := pathLen -1;
      while p[i].Y = p[0].Y do dec(i);
      P0IsMinima := p[i].Y < p[0].Y; //p[0].Y is a minima
    end else
    begin
      i := pathLen -1;
      while p[i].Y = p[0].Y do dec(i);
      P0IsMaxima := p[i].Y > p[0].Y; //p[0].Y is a maxima
    end;
  end;

  GetMem(result, sizeof(TVertex) * pathLen);
  result[0].Pt := p[0];
  result[0].flags := [];

  if isOpen then
  begin
    include(result[0].flags, vfStart);
    if goingUp then
      AddLocMin(@result[0]) else
      include(result[0].flags, vfMaxima);
  end;

  //nb: polygon orientation is determined later (see InsertLocalMinimaIntoAEL).
  i := 0;
  for j := 1 to pathLen -1 do
  begin
    if PointsEqual(p[j], result[i].Pt) then continue; //ie skips duplicates
    RangeCheck(p[j]);
    result[j].Pt := p[j];
    result[j].flags := [];
    result[i].next := @result[j];
    result[j].prev := @result[i];
    if (p[j].Y > p[i].Y) and goingUp then
    begin
      include(result[i].flags, vfMaxima);
      goingUp := false;
    end
    else if (p[j].Y < p[i].Y) and not goingUp then
    begin
      goingUp := true;
      AddLocMin(@result[i]);
    end;
    i := j;
  end;
  //i: index of the last vertex in the path.
  result[i].next := @result[0];
  result[0].prev := @result[i];

  if isOpen then
  begin
    include(result[i].flags, vfEnd);
    if goingUp then
      include(result[i].flags, vfMaxima) else
      AddLocMin(@result[i]);
  end else
  begin
    if goingUp then
    begin
      //going up so find local maxima ...
      v := @result[i];
      while (v.Next.Pt.Y <= v.Pt.Y) do v := v.next;
      include(v.flags, vfMaxima);
      if P0IsMinima then AddLocMin(@result[0]);
    end else
    begin
      //going down so find local minima ...
      v := @result[i];
      while (v.Next.Pt.Y >= v.Pt.Y) do v := v.next;
      AddLocMin(v);
      if P0IsMaxima then include(result[0].flags, vfMaxima);
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddPath(const path: TPath; PolyType: TPolyType;
  isOpen: Boolean);
var
  vertices: PVertexArray;
begin
  FLocMinListSorted := false;
  vertices := PathToVertexArray(path, polyType, isOpen);
  if not assigned(vertices) then Exit;
  FVertexList.Add(vertices);
  inc(FPathCount);
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddPaths(const paths: TPaths; polyType: TPolyType;
  isOpen: Boolean);
var
  i: integer;
begin
  for i := 0 to high(paths) do AddPath(paths[i], polyType, isOpen);
end;
//------------------------------------------------------------------------------

function TClipper2.IsContributing(Edge: PActive): Boolean;
var
  pft: TPolyFillType;
begin
  pft := FFillType;
  case pft of
    pftEvenOdd: Result := not IsOpen(Edge) or (Edge.WindCnt = 1);
    pftNonZero: Result := abs(Edge.WindCnt) = 1;
    pftPositive: Result := (Edge.WindCnt = 1);
    else Result := (Edge.WindCnt = -1);
  end;
  if not Result then Exit;

  case FClipType of
    ctIntersection:
      case pft of
        pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 <> 0);
        pftPositive: Result := (Edge.WindCnt2 > 0);
        pftNegative: Result := (Edge.WindCnt2 < 0);
      end;
    ctUnion:
      case pft of
        pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 = 0);
        pftPositive: Result := (Edge.WindCnt2 <= 0);
        pftNegative: Result := (Edge.WindCnt2 >= 0);
      end;
    ctDifference:
      if Edge.LocMin.PolyType = ptSubject then
        case pft of
          pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 = 0);
          pftPositive: Result := (Edge.WindCnt2 <= 0);
          pftNegative: Result := (Edge.WindCnt2 >= 0);
        end
      else
        case pft of
          pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 <> 0);
          pftPositive: Result := (Edge.WindCnt2 > 0);
          pftNegative: Result := (Edge.WindCnt2 < 0);
        end;
      ctXor:
        if IsOpen(Edge) then //XOr always contributing unless open
          case pft of
            pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 = 0);
            pftPositive: Result := (Edge.WindCnt2 <= 0);
            pftNegative: Result := (Edge.WindCnt2 >= 0);
          end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.SetWindingCount(Edge: PActive);
var
  E, E2: PActive;
  Inside: Boolean;
  pft: TPolyFillType;
begin
  E := Edge.PrevInAEL;
  //find the Edge of the same PolyType that immediately preceeds 'Edge' in AEL
  while Assigned(E) and (not IsSamePolyType(E, Edge) or IsOpen(E)) do
    E := E.PrevInAEL;
  if not Assigned(E) then
  begin
    if IsOpen(Edge) then
    begin
      pft := FFillType;
      if pft = pftNegative then
        Edge.WindCnt := -1 else
        Edge.WindCnt := 1;
    end
    else
      Edge.WindCnt := Edge.WindDelta;
    Edge.WindCnt2 := 0;
    E := FActiveEdges; //ie get ready to calc WindCnt2
  end
  else if IsOpen(Edge) and (FClipType <> ctUnion) then
  begin
    Edge.WindCnt := 1;
    Edge.WindCnt2 := E.WindCnt2;
    E := E.NextInAEL; //ie get ready to calc WindCnt2
  end
  else if FFillType = pftEvenOdd then
  begin
    //even-odd filling ...
    if IsOpen(Edge) then  //if edge is part of a line
    begin
      //are we inside a subj polygon ...
      Inside := true;
      E2 := E.PrevInAEL;
      while assigned(E2) do
      begin
        if IsSamePolyType(E2, E) and not IsOpen(E2) then
          Inside := not Inside;
        E2 := E2.PrevInAEL;
      end;
      if Inside then Edge.WindCnt := 0
      else Edge.WindCnt := 1;
    end
    else //else a polygon
    begin
      Edge.WindCnt := Edge.WindDelta;
    end;
    Edge.WindCnt2 := E.WindCnt2;
    E := E.NextInAEL; //ie get ready to calc WindCnt2
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    if (E.WindCnt * E.WindDelta < 0) then
    begin
      //prev edge is 'decreasing' WindCount (WC) toward zero
      //so we're outside the previous polygon ...
      if (Abs(E.WindCnt) > 1) then
      begin
        //outside prev poly but still inside another.
        //when reversing direction of prev poly use the same WC
        if (E.WindDelta * Edge.WindDelta < 0) then
          Edge.WindCnt := E.WindCnt
        //otherwise continue to 'decrease' WC ...
        else Edge.WindCnt := E.WindCnt + Edge.WindDelta;
      end
      else
        //now outside all polys of same polytype so set own WC ...
        if IsOpen(Edge) then Edge.WindCnt := 1
        else Edge.WindCnt := Edge.WindDelta;
    end else
    begin
      //prev edge is 'increasing' WindCount (WC) away from zero
      //so we're inside the previous polygon ...
      if IsOpen(Edge) then
      begin
        if (E.WindCnt < 0) then Edge.WindCnt := E.WindCnt -1
        else Edge.WindCnt := E.WindCnt +1;
      end
      //if wind direction is reversing prev then use same WC
      else if (E.WindDelta * Edge.WindDelta < 0) then
        Edge.WindCnt := E.WindCnt
      //otherwise add to WC ...
      else Edge.WindCnt := E.WindCnt + Edge.WindDelta;
    end;
    Edge.WindCnt2 := E.WindCnt2;
    E := E.NextInAEL; //ie get ready to calc WindCnt2
  end;

  //update WindCnt2 ...
  if FFillType = pftEvenOdd then
  begin
    //even-odd filling ...
    while (E <> Edge) do
    begin
      if IsOpen(E) then //do nothing (ie ignore lines)
      else if Edge.WindCnt2 = 0 then Edge.WindCnt2 := 1
      else Edge.WindCnt2 := 0;
      E := E.NextInAEL;
    end;
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    while (E <> Edge) do
    begin
      Inc(Edge.WindCnt2, E.WindDelta);
      E := E.NextInAEL;
    end;
  end;
end;
//------------------------------------------------------------------------------

function E2InsertsBeforeE1(E1, E2: PActive; preferLeft: Boolean): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if E2.Curr.X = E1.Curr.X then
  begin
    if preferLeft then
      Result := GetTopDeltaX(E1, E2) <= 0 else
      Result := GetTopDeltaX(E1, E2) < 0;
  end else
    Result := E2.Curr.X < E1.Curr.X;
end;
//----------------------------------------------------------------------

procedure TClipper2.InsertLocalMinimaIntoAEL(const BotY: cInt);

  procedure InsertEdgeIntoAEL(Edge, StartEdge: PActive; preferLeft: Boolean);
  begin
    if not Assigned(FActiveEdges) then
    begin
      Edge.PrevInAEL := nil;
      Edge.NextInAEL := nil;
      FActiveEdges := Edge;
    end
    else if not Assigned(StartEdge) and
      E2InsertsBeforeE1(FActiveEdges, Edge, preferLeft) then
    begin
      Edge.PrevInAEL := nil;
      Edge.NextInAEL := FActiveEdges;
      FActiveEdges.PrevInAEL := Edge;
      FActiveEdges := Edge;
    end else
    begin
      if not Assigned(StartEdge) then StartEdge := FActiveEdges;
      while Assigned(StartEdge.NextInAEL) and
        not E2InsertsBeforeE1(StartEdge.NextInAEL, Edge, preferLeft) do
        begin
          StartEdge := StartEdge.NextInAEL;
          preferLeft := false; //if there's one intervening then allow all
        end;
      Edge.NextInAEL := StartEdge.NextInAEL;
      if Assigned(StartEdge.NextInAEL) then
        StartEdge.NextInAEL.PrevInAEL := Edge;
      Edge.PrevInAEL := StartEdge;
      StartEdge.NextInAEL := Edge;
    end;
  end;
  //----------------------------------------------------------------------

var
  E: PActive;
  LeftB, RightB, tmp: PActive;
  LocMin: PLocalMinimum;
  contributing: Boolean;
begin
  //Add any local minima at BotY ...
  while PopLocalMinima(BotY, LocMin) do
  begin
    if not (vfStart in LocMin.vertex.flags) then
    begin
      new(LeftB);
      FillChar(LeftB^, sizeof(TActive), 0);
      LeftB.LocMin := LocMin;
      LeftB.OutRec := nil;
      LeftB.Bot := LocMin.vertex.Pt;
      LeftB.vertTop := LocMin.vertex.prev;  //ie a descending bound initially
      LeftB.Top := LeftB.vertTop.Pt;
      LeftB.Curr := LeftB.Bot;
      LeftB.WindDelta := -1;
      SetDx(LeftB);
      if LocMin.IsOpen then include(LeftB.Flags, afOpen);
    end else
      LeftB := nil;

    if not (vfEnd in LocMin.vertex.flags) then
    begin
      new(RightB);
      FillChar(RightB^, sizeof(TActive), 0);
      RightB.LocMin := LocMin;
      RightB.OutRec := nil;
      RightB.Bot := LocMin.vertex.Pt;
      RightB.vertTop := LocMin.vertex.next; //ie an ascending bound initially
      RightB.Top := RightB.vertTop.Pt;
      RightB.Curr := RightB.Bot;
      RightB.WindDelta := 1;
      SetDx(RightB);
      if LocMin.IsOpen then include(RightB.Flags, afOpen);
    end else
      RightB := nil;

    //now swap left and right bounds according to orientation ...
    if assigned(LeftB) and assigned(RightB) then
    begin
      //swap bounds when oriented clockwise (ie when left bound is ascending)
      if (IsHorizontal(LeftB) and (LeftB.Top.X > LeftB.Bot.X)) or
       (not IsHorizontal(LeftB) and (LeftB.Dx < RightB.Dx)) then
       begin
          tmp := LeftB;
          LeftB := RightB;
          RightB := tmp;
       end;
    end;

    if not assigned(LeftB) then
    begin
      tmp := LeftB;
      LeftB := RightB;
      RightB := tmp;
    end;

    InsertEdgeIntoAEL(LeftB, nil, false);
    SetWindingCount(LeftB);
    RightB.WindCnt := LeftB.WindCnt;
    RightB.WindCnt2 := LeftB.WindCnt2;
    contributing := IsContributing(LeftB);
    InsertEdgeIntoAEL(RightB, LeftB, false);


    if assigned(RightB) then
    begin
      if contributing then
        AddLocalMinPoly(LeftB, RightB, LeftB.Bot);

      if IsHorizontal(RightB) then
        AddEdgeToSEL(RightB) else
        InsertScanLine(RightB.Top.Y);

    end
    else if IsContributing(LeftB) then
      AddOutPt(LeftB, LeftB.Bot); //an open path

    if IsHorizontal(LeftB) then
      AddEdgeToSEL(LeftB) else
      InsertScanLine(LeftB.Top.Y);

    if (LeftB.NextInAEL <> RightB) then
    begin
      //intersect edges that are between left and right bounds ...
      E := LeftB.NextInAEL;
      while (E <> RightB) do
      begin
        //nb: For calculating winding counts etc, IntersectEdges() assumes
        //that param1 will be to the right of param2 ABOVE the intersection ...
        IntersectEdges(RightB, E, RightB.Bot);
        E := E.NextInAEL;
      end;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DeleteFromAEL(E: PActive);
var
  AelPrev, AelNext: PActive;
begin
  AelPrev := E.PrevInAEL;
  AelNext := E.NextInAEL;
  if not Assigned(AelPrev) and not Assigned(AelNext) and
    (E <> FActiveEdges) then Exit; //already deleted
  if Assigned(AelPrev) then AelPrev.NextInAEL := AelNext
  else FActiveEdges := AelNext;
  if Assigned(AelNext) then AelNext.PrevInAEL := AelPrev;
  E.NextInAEL := nil;
  E.PrevInAEL := nil;
  Dispose(E);
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddOutPt(e: PActive; const pt: TIntPoint);
var
  PrevOp, op, op2: POutPt;
  ToFront: Boolean;
begin
  if not assigned(e.OutRec) or not assigned(e.OutRec.Pts) then
    raise EClipperLibException.Create(rsClippingErr);
  ToFront := IsLeftSide(e);
  op := e.OutRec.Pts;
  if ToFront then PrevOp := op else PrevOp := op.Prev;
  if PointsEqual(pt, PrevOp.Pt) then Exit;
  new(op2);
  op2.Pt := pt;
  op2.Next := op;
  op2.Prev := op.Prev;
  op.Prev.Next := op2;
  op.Prev := op2;
  if ToFront then e.OutRec.Pts := op2;
 end;
//------------------------------------------------------------------------------

procedure EndOutRec(outRec: POutRec);
begin
  outRec.LeftE.OutRec := nil;
  if assigned(outRec.RightE) then outRec.RightE.OutRec := nil;
  outRec.LeftE := nil;
  outRec.RightE := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddLocalMinPoly(E1, E2: PActive; const Pt: TIntPoint);
begin
  StartOutRec(E1, E2, Pt);
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddLocalMaxPoly(E1, E2: PActive; const Pt: TIntPoint);
begin
  AddOutPt(E1, Pt);
  if (E1.OutRec = E2.OutRec) then
    EndOutRec(E1.OutRec)
  else if e1.OutRec.Idx < e2.OutRec.Idx then
    AppendPath(E1, E2) else
    AppendPath(E2, E1);
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddEdgeToSEL(Edge: PActive);
begin
  //SEL pointers in PActive are use to build transient lists of horizontal edges.
  //However, since we don't need to worry about processing order, all additions
  //are made to the front of the list ...
  if not Assigned(FSortedEdges) then
  begin
    FSortedEdges := Edge;
    Edge.PrevInSEL := nil;
    Edge.NextInSEL := nil;
  end else
  begin
    Edge.NextInSEL := FSortedEdges;
    Edge.PrevInSEL := nil;
    FSortedEdges.PrevInSEL := Edge;
    FSortedEdges := Edge;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.PopEdgeFromSEL(out E: PActive): Boolean;
begin
  //Pop edge from front of SEL (ie SEL is a FILO list)
  E := FSortedEdges;
  Result := assigned(E);
  if not Result then Exit;
  FSortedEdges := E.NextInSEL;
  if Assigned(FSortedEdges) then FSortedEdges.PrevInSEL := nil;
  E.NextInSEL := nil;
  E.PrevInSEL := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper2.CopyAELToSEL;
var
  E: PActive;
begin
  E := FActiveEdges;
  FSortedEdges := E;
  while Assigned(E) do
  begin
    E.PrevInSEL := E.PrevInAEL;
    E.NextInSEL := E.NextInAEL;
    E := E.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.UpdateEdgeIntoAEL(var E: PActive);
begin
  E.Bot := E.Top;
  if E.WindDelta < 0 then
    E.vertTop := E.vertTop.prev else
    E.vertTop := E.vertTop.next;
  E.Top := E.vertTop.Pt;
  E.Curr := E.Bot;
  SetDx(E);
  if not IsHorizontal(E) then InsertScanLine(E.Top.Y);
end;
//------------------------------------------------------------------------------

procedure TClipper2.SwapOutRecs(E1, E2: PActive);
var
  or1, or2: POutRec;
  e: PActive;
begin
  or1 := E1.OutRec;
  or2 := E2.OutRec;
  if (or1 = or2) then
  begin
    e := or1.LeftE;
    or1.LeftE := or1.RightE;
    or1.RightE := e;
    Exit;
  end;
  if assigned(or1) then
  begin
    if E1 = or1.LeftE then
      or1.LeftE := E2 else
      or1.RightE := E2;
  end;
  if assigned(or2) then
  begin
    if E2 = or2.LeftE then
      or2.LeftE := E1 else
      or2.RightE := E1;
  end;
  E1.OutRec := or2;
  E2.OutRec := or1;
end;
//------------------------------------------------------------------------------

procedure TClipper2.IntersectEdges(E1,E2: PActive; Pt: TIntPoint);
var
  E1Contributing, E2contributing: Boolean;
  E1Wc, E2Wc, E1Wc2, E2Wc2: Integer;
begin
  {IntersectEdges}
  //E1 will be to the left of E2 BELOW the intersection. Therefore E1 is before
  //E2 in AEL except when E1 is being inserted at the intersection point ...

  E1Contributing := assigned(E1.OutRec);
  E2contributing := assigned(E2.OutRec);

  E1.Curr := Pt;
  E2.Curr := Pt;

{$IFDEF use_xyz}
        SetZ(Pt, E1, E2, FZFillCallback);
{$ENDIF}

{$IFDEF use_lines}
  //if either edge is on an OPEN path ...
  if IsOpen(E1) or IsOpen(E2) then
  begin
    //ignore subject-subject open path intersections ...
    if IsOpen(E1) AND IsOpen(E2) then Exit
    //if intersecting a subj line with a subj poly ...
    else if IsSamePolyType(E1, E2) and
      (E1.WindDelta <> E2.WindDelta) and (FClipType = ctUnion) then
    begin
      if IsOpen(E1) then
      begin
        if (E2Contributing) then
        begin
          AddOutPt(E1, pt);
          if (E1Contributing) then E1.OutRec := nil; //todo check
        end;
      end else
      begin
        if (E1Contributing) then
        begin
          AddOutPt(E2, pt);
          if (E2Contributing) then E2.OutRec := nil; //todo check
        end;
      end;
    end
    else if not IsSamePolyType(E1, E2) then
    begin
      //toggle subj open path OutIdx on/off when Abs(clip.WndCnt) = 1 ...
      if IsOpen(E1) and (Abs(E2.WindCnt) = 1) and
       ((FClipType <> ctUnion) or (E2.WindCnt2 = 0)) then
      begin
        AddOutPt(E1, Pt);
        if E1Contributing then E1.OutRec := nil; //todo check
      end
      else if IsOpen(E2) and (Abs(E1.WindCnt) = 1) and
       ((FClipType <> ctUnion) or (E1.WindCnt2 = 0)) then
      begin
        AddOutPt(E2, Pt);
        if E2Contributing then E2.OutRec := nil; //todo check
      end
    end;
    Exit;
  end;
{$ENDIF}

  //update winding counts...
  //assumes that E1 will be to the right of E2 ABOVE the intersection
  if IsSamePolyType(E1, E2) then
  begin
    if FFillType = pftEvenOdd then
    begin
      E1Wc := E1.WindCnt;
      E1.WindCnt := E2.WindCnt;
      E2.WindCnt := E1Wc;
    end else
    begin
      if E1.WindCnt + E2.WindDelta = 0 then
        E1.WindCnt := -E1.WindCnt else
        Inc(E1.WindCnt, E2.WindDelta);
      if E2.WindCnt - E1.WindDelta = 0 then
        E2.WindCnt := -E2.WindCnt else
        Dec(E2.WindCnt, E1.WindDelta);
    end;
  end else
  begin
    if FFillType <> pftEvenOdd then Inc(E1.WindCnt2, E2.WindDelta)
    else if E1.WindCnt2 = 0 then E1.WindCnt2 := 1
    else E1.WindCnt2 := 0;

    if FFillType <> pftEvenOdd then Dec(E2.WindCnt2, E1.WindDelta)
    else if E2.WindCnt2 = 0 then E2.WindCnt2 := 1
    else E2.WindCnt2 := 0;
  end;

  case FFillType of
    pftPositive:
      begin
        E1Wc := E1.WindCnt;
        E2Wc := E2.WindCnt;
      end;
    pftNegative:
      begin
        E1Wc := -E1.WindCnt;
        E2Wc := -E2.WindCnt;
      end;
    else
      begin
        E1Wc := abs(E1.WindCnt);
        E2Wc := abs(E2.WindCnt);
      end;
  end;

  if E1Contributing and E2Contributing then
  begin
    if not (E1Wc in [0,1]) or not (E2Wc in [0,1]) or
      (not IsSamePolyType(E1, E2) and (fClipType <> ctXor)) then
    begin
      AddLocalMaxPoly(E1, E2, Pt);
    end else
    begin
      AddOutPt(E1, Pt);
      AddOutPt(E2, Pt);
      SwapOutRecs(E1, E2);
    end;
  end else if E1Contributing then
  begin
    if (E2Wc = 0) or (E2Wc = 1) then
    begin
      AddOutPt(E1, Pt);
      SwapOutRecs(E1, E2);
    end;
  end
  else if E2contributing then
  begin
    if (E1Wc = 0) or (E1Wc = 1) then
    begin
      AddOutPt(E2, Pt);
      SwapOutRecs(E1, E2);
    end;
  end
  else if  ((E1Wc = 0) or (E1Wc = 1)) and ((E2Wc = 0) or (E2Wc = 1)) then
  begin
    //neither Edge is currently contributing ...
    case FFillType of
      pftPositive:
      begin
        E1Wc2 := E1.WindCnt2;
        E2Wc2 := E2.WindCnt2;
      end;
      pftNegative:
      begin
        E1Wc2 := -E1.WindCnt2;
        E2Wc2 := -E2.WindCnt2;
      end
      else
      begin
        E1Wc2 := abs(E1.WindCnt2);
        E2Wc2 := abs(E2.WindCnt2);
      end;
    end;

    if not IsSamePolyType(E1, E2) then
    begin
      AddLocalMinPoly(E1, E2, Pt);
    end
    else if (E1Wc = 1) and (E2Wc = 1) then
      case FClipType of
        ctIntersection:
          if (E1Wc2 > 0) and (E2Wc2 > 0) then
            AddLocalMinPoly(E1, E2, Pt);
        ctUnion:
          if (E1Wc2 <= 0) and (E2Wc2 <= 0) then
            AddLocalMinPoly(E1, E2, Pt);
        ctDifference:
          if ((E1.LocMin.PolyType = ptClip) and (E1Wc2 > 0) and (E2Wc2 > 0)) or
            ((E1.LocMin.PolyType = ptSubject) and (E1Wc2 <= 0) and (E2Wc2 <= 0)) then
              AddLocalMinPoly(E1, E2, Pt);
        ctXor:
          AddLocalMinPoly(E1, E2, Pt);
      end
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.Execute(clipType: TClipType; out solution: TPaths;
  fillType: TPolyFillType = pftEvenOdd): Boolean;
var
  Y: cInt;

 begin
  Result := False;
  solution := nil;
  if FExecuteLocked then Exit;
  //nb: Open paths can only be returned via the PolyTree structure ...
  if FHasOpenPaths then raise EClipperLibException.Create(rsOpenPathErr);
  try try
    FExecuteLocked := True;
    FFillType := fillType;
    FClipType := clipType;

    Reset;
    FSortedEdges := nil;
    if not PopScanLine(Y) then Exit;
     ////////////////////////////////////////////////////////
    while true do
    begin
      InsertLocalMinimaIntoAEL(Y);
      if assigned(FSortedEdges) then ProcessHorizontals(Y);
       if not PopScanLine(Y) then break;
      ProcessIntersections(Y);
      DoTopOfScanbeam(Y);
    end;
    ////////////////////////////////////////////////////////

    solution := BuildResult;
    Result := True;
  except
    //cleanup ...
    while assigned(FActiveEdges) do DeleteFromAEL(FActiveEdges);
    solution := nil;
  end;
  finally
    DisposeScanLineList;
    DisposeAllOutRecs;
    FExecuteLocked := False;
   end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessIntersections(const TopY: cInt);
begin
  try
    BuildIntersectList(TopY);
    if (FIntersectList.Count = 0) then Exit
    else if FixupIntersectionOrder then ProcessIntersectList()
    else raise EClipperLibException.Create(rsClippingErr);
  finally
    DisposeIntersectNodes; //clean up if there's been an error
    FSortedEdges := nil;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeIntersectNodes;
var
  I: Integer;
begin
  for I := 0 to FIntersectList.Count - 1 do
    Dispose(PIntersectNode(FIntersectList[I]));
  FIntersectList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper2.BuildIntersectList(const TopY: cInt);
var
  E, eNext: PActive;
  Pt: TIntPoint;
  IsModified: Boolean;
  NewNode: PIntersectNode;
begin
  if not Assigned(fActiveEdges) then Exit;

  //prepare for sorting ...
  E := FActiveEdges;
  FSortedEdges := E;
  while Assigned(E) do
  begin
    E.PrevInSEL := E.PrevInAEL;
    E.NextInSEL := E.NextInAEL;
    E.Curr.X := TopX(E, TopY);
    E := E.NextInAEL;
  end;

  //bubblesort (because adjacent swaps are required) ...
  repeat
    IsModified := False;
    E := FSortedEdges;
    while Assigned(E.NextInSEL) do
    begin
      eNext := E.NextInSEL;
      if (E.Curr.X > eNext.Curr.X) then
      begin
        pt := GetIntersectPoint(E, eNext);
        if Pt.Y < TopY then
          Pt := IntPoint(TopX(E, TopY), TopY);
        new(NewNode);
        NewNode.Edge1 := E;
        NewNode.Edge2 := eNext;
        NewNode.Pt := Pt;
        FIntersectList.Add(NewNode);

        SwapPositionsInSEL(E, eNext);
        IsModified := True;
      end else
        E := eNext;
    end;
    if Assigned(E.PrevInSEL) then
      E.PrevInSEL.NextInSEL := nil
    else Break;
  until not IsModified;
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessIntersectList;
var
  I: Integer;
begin
  for I := 0 to FIntersectList.Count - 1 do
  begin
    with PIntersectNode(FIntersectList[I])^ do
    begin
      IntersectEdges(Edge1, Edge2, Pt);
      SwapPositionsInAEL(Edge1, Edge2);
      //todo: check here for double contributing parallel edges
    end;
    dispose(PIntersectNode(FIntersectList[I]));
  end;
  FIntersectList.Clear;
end;
//------------------------------------------------------------------------------

function EdgesAdjacent(Inode: PIntersectNode): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (Inode.Edge1.NextInSEL = Inode.Edge2) or
    (Inode.Edge1.PrevInSEL = Inode.Edge2);
end;
//------------------------------------------------------------------------------

function IntersectListSort(Node1, Node2: Pointer): Integer;
var
  i: cInt;
begin
  i := PIntersectNode(Node2).Pt.Y - PIntersectNode(Node1).Pt.Y;
  if i < 0 then Result := -1
  else if i > 0 then Result := 1
  else Result := 0;
end;
//------------------------------------------------------------------------------

function TClipper2.FixupIntersectionOrder: Boolean;
var
  I, J, Cnt: Integer;
  Node: PIntersectNode;
begin
  //pre-condition: intersections are sorted bottom-most first.
  //Now it's crucial that intersections are made only between adjacent edges,
  //and to ensure this the order of intersections may need adjusting ...
  Result := True;
  Cnt := FIntersectList.Count;
  if Cnt < 2 then exit;

  CopyAELToSEL;
  FIntersectList.Sort(IntersectListSort);
  for I := 0 to Cnt - 1 do
  begin
    if not EdgesAdjacent(FIntersectList[I]) then
    begin
      J := I + 1;
      while (J < Cnt) and not EdgesAdjacent(FIntersectList[J]) do inc(J);
      if J = Cnt then
      begin
        Result := False;
        Exit; //error!!
      end;
      //Swap IntersectNodes ...
      Node := FIntersectList[I];
      FIntersectList[I] := FIntersectList[J];
      FIntersectList[J] := Node;
    end;
    with PIntersectNode(FIntersectList[I])^ do
      SwapPositionsInSEL(Edge1, Edge2);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.SwapPositionsInAEL(E1, E2: PActive);
var
  Prev,Next: PActive;
begin
  //check that one or other edge hasn't already been removed from AEL ...
  if (E1.NextInAEL = E1.PrevInAEL) or (E2.NextInAEL = E2.PrevInAEL) then
    Exit;

  if E1.NextInAEL = E2 then
  begin
    Next := E2.NextInAEL;
    if Assigned(Next) then Next.PrevInAEL := E1;
    Prev := E1.PrevInAEL;
    if Assigned(Prev) then Prev.NextInAEL := E2;
    E2.PrevInAEL := Prev;
    E2.NextInAEL := E1;
    E1.PrevInAEL := E2;
    E1.NextInAEL := Next;
  end
  else if E2.NextInAEL = E1 then
  begin
    Next := E1.NextInAEL;
    if Assigned(Next) then Next.PrevInAEL := E2;
    Prev := E2.PrevInAEL;
    if Assigned(Prev) then Prev.NextInAEL := E1;
    E1.PrevInAEL := Prev;
    E1.NextInAEL := E2;
    E2.PrevInAEL := E1;
    E2.NextInAEL := Next;
  end else
  begin
    Next := E1.NextInAEL;
    Prev := E1.PrevInAEL;
    E1.NextInAEL := E2.NextInAEL;
    if Assigned(E1.NextInAEL) then E1.NextInAEL.PrevInAEL := E1;
    E1.PrevInAEL := E2.PrevInAEL;
    if Assigned(E1.PrevInAEL) then E1.PrevInAEL.NextInAEL := E1;
    E2.NextInAEL := Next;
    if Assigned(E2.NextInAEL) then E2.NextInAEL.PrevInAEL := E2;
    E2.PrevInAEL := Prev;
    if Assigned(E2.PrevInAEL) then E2.PrevInAEL.NextInAEL := E2;
  end;
  if not Assigned(E1.PrevInAEL) then FActiveEdges := E1
  else if not Assigned(E2.PrevInAEL) then FActiveEdges := E2;
end;
//------------------------------------------------------------------------------

procedure TClipper2.SwapPositionsInSEL(E1, E2: PActive);
var
  Prev,Next: PActive;
begin
  if E1.NextInSEL = E2 then
  begin
    Next := E2.NextInSEL;
    if Assigned(Next) then Next.PrevInSEL := E1;
    Prev := E1.PrevInSEL;
    if Assigned(Prev) then Prev.NextInSEL := E2;
    E2.PrevInSEL := Prev;
    E2.NextInSEL := E1;
    E1.PrevInSEL := E2;
    E1.NextInSEL := Next;
  end
  else if E2.NextInSEL = E1 then
  begin
    Next := E1.NextInSEL;
    if Assigned(Next) then Next.PrevInSEL := E2;
    Prev := E2.PrevInSEL;
    if Assigned(Prev) then Prev.NextInSEL := E1;
    E1.PrevInSEL := Prev;
    E1.NextInSEL := E2;
    E2.PrevInSEL := E1;
    E2.NextInSEL := Next;
  end else
  begin
    Next := E1.NextInSEL;
    Prev := E1.PrevInSEL;
    E1.NextInSEL := E2.NextInSEL;
    if Assigned(E1.NextInSEL) then E1.NextInSEL.PrevInSEL := E1;
    E1.PrevInSEL := E2.PrevInSEL;
    if Assigned(E1.PrevInSEL) then E1.PrevInSEL.NextInSEL := E1;
    E2.NextInSEL := Next;
    if Assigned(E2.NextInSEL) then E2.NextInSEL.PrevInSEL := E2;
    E2.PrevInSEL := Prev;
    if Assigned(E2.PrevInSEL) then E2.PrevInSEL.NextInSEL := E2;
  end;
  if not Assigned(E1.PrevInSEL) then FSortedEdges := E1
  else if not Assigned(E2.PrevInSEL) then FSortedEdges := E2;
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessHorizontals(Y: cInt);
var
  E: PActive;
begin
  while PopEdgeFromSEL(E) do
    ProcessHorizontal(E);
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessHorizontal(HorzEdge: PActive);
var
  e, eNext, maxPair: PActive;
  horzLeft, horzRight: cInt;
  direction: TDirection;
  pt: TIntPoint;
  isMaxima: Boolean;

  procedure ResetHorzDir;
  var
    e: PActive;
  begin
    if (HorzEdge.Bot.X = HorzEdge.Top.X) then
    begin
      //the horizontal edge is going nowhere ...
      horzLeft := HorzEdge.Curr.X;
      horzRight := HorzEdge.Curr.X;
      e := HorzEdge.NextInAEL;
      while assigned(e) and (e <> maxPair) do
        e := e.NextInAEL;
      if assigned(e) then
        direction := dLeftToRight else
        direction := dRightToLeft;
    end
    else if HorzEdge.Curr.X < HorzEdge.Top.X then
    begin
      horzLeft := HorzEdge.Curr.X;
      horzRight := HorzEdge.Top.X;
      direction := dLeftToRight;
    end else
    begin
      horzLeft := HorzEdge.Top.X;
      horzRight := HorzEdge.Curr.X;
      direction := dRightToLeft;
    end;
  end;
  //------------------------------------------------------------------------

begin
(*******************************************************************************
* Notes: Horizontal edges (HEs) at scanline intersections (ie at the top or    *
* bottom of a scanbeam) are processed as if layered. The order in which HEs    *
* are processed doesn't matter. HEs intersect with the bottom vertices of      *
* other HEs [#] and with non-horizontal edges [*]. Once these intersections    *
* are completed, intermediate HEs are 'promoted' to the next edge in their     *
* bounds, and they in turn may be intersected [%] by other HEs.                *
*                                                                              *
* eg: 3 horizontals at a scanline:  /   |                      /          /    *
*              |                   /    |    (HE3) o==========%==========o     *
*              o=======o (HE2)    /     |        /          /                  *
*         o============#=========*======*=======#==========o (HE1)             *
*        /             |        /       |     /                                *
*******************************************************************************)

  //with closed paths, simplify consecutive horizontals into a 'single' edge ...
  if not HorzEdge.LocMin.IsOpen then
  begin
    pt := HorzEdge.Bot;
    while not (vfMaxima in HorzEdge.vertTop.flags) and
      (NextVertex(HorzEdge).Pt.Y = pt.Y) do
        UpdateEdgeIntoAEL(HorzEdge);
    HorzEdge.Bot := pt;
    HorzEdge.Curr := pt;
  end;

  if (vfMaxima in HorzEdge.vertTop.flags) then
  begin
    maxPair := GetMaximaPair(HorzEdge);
    if assigned(maxPair) then
    begin
      SetMaximaFlag(HorzEdge);
      SetMaximaFlag(maxPair);
    end;
  end else
    maxPair := nil;

  if assigned(HorzEdge.OutRec) then AddOutPt(HorzEdge, HorzEdge.Curr);
  ResetHorzDir;

  while true do //loops through consec. horizontal edges (if open)
  begin
    isMaxima := vfMaxima in HorzEdge.vertTop.flags;
    if direction = dRightToLeft then
      e := HorzEdge.PrevInAEL else
      e := HorzEdge.NextInAEL;

    while assigned(e) do
    begin
      //if we've gone past the end of the horizontal (nb can't be a maxima)
      if ((direction = dLeftToRight) and (e.Curr.X > horzRight)) or
        ((direction = dRightToLeft) and (e.Curr.X < horzLeft)) then break;

      if (E.Curr.X = HorzEdge.Top.X) and not isMaxima and not IsHorizontal(e) then
      begin
        //also break if we've got to the end of an intermediate horizontal edge ...
        pt := NextVertex(HorzEdge).Pt;
        if((direction = dLeftToRight) and (TopX(E, pt.Y) >= pt.X)) or
          ((direction = dRightToLeft) and (TopX(E, pt.Y) <= pt.X)) then Break;
      end;

      if (e = maxPair) then
      begin
        if assigned(HorzEdge.OutRec)  then
          AddLocalMaxPoly(HorzEdge, e, HorzEdge.Top);
        DeleteFromAEL(HorzEdge);
        DeleteFromAEL(e);
        Exit;
      end;

      if IsMaximaFlagged(e) then
        //do nothing (nb: a maxima from another horizontal)
      else if (direction = dLeftToRight) then
      begin
        pt := IntPoint(e.Curr.X, HorzEdge.Curr.Y);
        IntersectEdges(HorzEdge, e, pt);
      end else
      begin
        pt := IntPoint(e.Curr.X, HorzEdge.Curr.Y);
        IntersectEdges(e, HorzEdge, pt);
      end;

      if direction = dRightToLeft then
        eNext := e.PrevInAEL else
        eNext := e.NextInAEL;
      SwapPositionsInAEL(HorzEdge, e);
      e := eNext;
    end;

    //check if we've finished with (consecutive) horizontals ...
    if NextVertex(HorzEdge).Pt.Y <> HorzEdge.Top.Y then Break;

    //still more horizontals in bound to process ...
    UpdateEdgeIntoAEL(HorzEdge);
    ResetHorzDir;
  end;

  //we've now reached the end of an intermediate horizontal ...
  if assigned(HorzEdge.OutRec) then AddOutPt(HorzEdge, HorzEdge.Top);
  UpdateEdgeIntoAEL(HorzEdge);
end;
//------------------------------------------------------------------------------

procedure TClipper2.DoTopOfScanbeam(Y: cInt);
var
  e: PActive;
begin
  e := FActiveEdges;
  while Assigned(e) do
  begin
    Exclude(E.Flags, afMaxima);
    //nb: E will never be horizontal at this point
    if (e.Top.Y = Y) then
    begin
      e.Curr := e.Top; //needed for horizontal processing
      if (vfMaxima in e.vertTop.flags) then
      begin
        e := DoMaxima(e); //TOP OF BOUND (MAXIMA)
        Continue;
      end else
      begin
        //INTERMEDIATE VERTEX ...
        UpdateEdgeIntoAEL(e);
        if assigned(e.OutRec) then AddOutPt(e, e.Bot);
        if IsHorizontal(e) then AddEdgeToSEL(e);
      end;
    end else
    begin
      e.Curr.Y := Y;
      e.Curr.X := TopX(e, Y);
      //if an edge touches a vertex in the previous bound, then insert an
      //OutPt here to avoid micro self-interesctions ...
      if assigned(e.OutRec) and assigned(e.PrevInAEL) and
        (e.PrevInAEL.Curr.X = e.Curr.X) and assigned(e.PrevInAEL.OutRec) then
          AddOutPt(e, e.Curr);
    end;
    e := e.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.DoMaxima(e: PActive): PActive;
var
  eNext, ePrev, eMaxPair: PActive;
begin
  ePrev := e.PrevInAEL;

{$IFDEF use_lines}
  if IsOpen(e) then
  begin
    if assigned(e.OutRec) then
      AddOutPt(e, e.Top);
    DeleteFromAEL(e);
    if assigned(ePrev) then
      Result := ePrev.NextInAEL else
      Result := FActiveEdges;
    Exit;
  end;
{$ENDIF}

  eMaxPair := GetMaximaPair(e);
  if not assigned(eMaxPair) then
  begin
    //EMaxPair is a horizontal ...
    Result := e.NextInAEL;
    Exit;
  end;
  eNext := e.NextInAEL;

  //non-horizontal maxima here.

  //process any edges between maxima pair ...
  while (eNext <> eMaxPair) do
  begin
    IntersectEdges(e, eNext, e.Top);
    SwapPositionsInAEL(e, eNext);
    eNext := e.NextInAEL;
  end;

  //here E.NextInAEL == ENext == EMaxPair ...
  if assigned(e.OutRec) or assigned(eMaxPair.OutRec) then
  begin
    if not assigned(e.OutRec) or not assigned(eMaxPair.OutRec) then
      raise EClipperLibException.Create(rsClippingErr) else //oops!
      AddLocalMaxPoly(e, eMaxPair, e.Top);
  end;

  DeleteFromAEL(e);
  DeleteFromAEL(eMaxPair);
  if assigned(ePrev) then
    Result := ePrev.NextInAEL else
    Result := FActiveEdges;
end;
//------------------------------------------------------------------------------

procedure ReversePolyPtLinks(PP: POutPt);
var
  Pp1,Pp2: POutPt;
begin
  if not Assigned(PP) then Exit;
  Pp1 := PP;
  repeat
    Pp2:= Pp1.Next;
    Pp1.Next := Pp1.Prev;
    Pp1.Prev := Pp2;
    Pp1 := Pp2;
  until Pp1 = PP;
end;
//------------------------------------------------------------------------------

procedure TClipper2.StartOutRec(e1, e2: PActive; const pt: TIntPoint);
var
  OutRec: POutRec;
  op    : POutPt;
begin
  new(OutRec);
  OutRec.IsOpen := afOpen in e1.Flags;
  OutRec.Pts := nil;
  OutRec.Idx := FPolyOutList.Add(OutRec);
  OutRec.LeftE := e1;
  OutRec.RightE := e2;
  e1.OutRec := OutRec;
  if assigned(e2) then e2.OutRec := OutRec;

  new(op);
  OutRec.Pts := op;
  op.Pt := pt;
  op.Next := op;
  op.Prev := op;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AppendPath(E1, E2: PActive);
var
  liveOR, deadOR: POutRec;
  P1_lt, P1_rt, P2_lt, P2_rt: POutPt;
begin
  liveOR := E1.OutRec;
  deadOR := E2.OutRec;

  //get the start and ends of both output polygons and
  //join E2 poly onto E1 poly and delete pointers to E2 ...

  P1_lt := liveOR.Pts;
  P2_lt := deadOR.Pts;
  P1_rt := P1_lt.Prev;
  P2_rt := P2_lt.Prev;

  if IsLeftSide(E1) then
  begin
    if IsLeftSide(E2) then
    begin
      //z y x a b c
      ReversePolyPtLinks(P2_lt);
      P2_lt.Next := P1_lt;
      P1_lt.Prev := P2_lt;
      P1_rt.Next := P2_rt;
      P2_rt.Prev := P1_rt;
      liveOR.Pts := P2_rt;
    end else
    begin
      //x y z a b c
      P2_rt.Next := P1_lt;
      P1_lt.Prev := P2_rt;
      P2_lt.Prev := P1_rt;
      P1_rt.Next := P2_lt;
      liveOR.Pts := P2_lt;
    end;
  end else
  begin
    if IsLeftSide(E2) then
    begin
      //a b c x y z
      P1_rt.Next := P2_lt;
      P2_lt.Prev := P1_rt;
      P1_lt.Prev := P2_rt;
      P2_rt.Next := P1_lt;
    end else
    begin
      //a b c z y x
      ReversePolyPtLinks(P2_lt);
      P1_rt.Next := P2_rt;
      P2_rt.Prev := P1_rt;
      P2_lt.Next := P1_lt;
      P1_lt.Prev := P2_lt;
    end;
  end;

  if IsLeftSide(E1) then
  begin
    if IsLeftSide(E2) then
      liveOR.LeftE := deadOR.RightE else
      liveOR.LeftE := deadOR.LeftE;
    if assigned(liveOR.LeftE.OutRec) then
      liveOR.LeftE.OutRec := liveOR;
  end else
  begin
    if IsLeftSide(E2) then
      liveOR.RightE := deadOR.RightE else
      liveOR.RightE := deadOR.LeftE;
    if assigned(liveOR.RightE.OutRec) then
      liveOR.RightE.OutRec := liveOR;
  end;

  e1.OutRec := nil;
  e2.OutRec := nil;
  deadOR.LeftE := nil; deadOR.RightE := nil; deadOR.Pts := nil;
end;
//------------------------------------------------------------------------------

function PointCount(Pts: POutPt): Integer;
var
  P: POutPt;
begin
  Result := 0;
  if not Assigned(Pts) then Exit;
  P := Pts;
  repeat
    Inc(Result);
    P := P.Next;
  until P = Pts;
end;
//------------------------------------------------------------------------------

function TClipper2.BuildResult: TPaths;
var
  I, J, K, Cnt: Integer;
  OutRec: POutRec;
  Op: POutPt;
begin
  J := 0;
  SetLength(Result, FPolyOutList.Count);
  for I := 0 to FPolyOutList.Count -1 do
    if Assigned(fPolyOutList[I]) then
    begin
      OutRec := FPolyOutList[I];
      if not assigned(OutRec.Pts) then Continue;

      Op := OutRec.Pts.Prev;
      Cnt := PointCount(Op);
      //fixup for duplicate start and end points ...
      if PointsEqual(Op.Pt, OutRec.Pts.Pt) then dec(Cnt);
      if (Cnt < 2) then Continue;
      SetLength(Result[J], Cnt);
      for K := 0 to Cnt -1 do
      begin
        Result[J][K] := Op.Pt;
        Op := Op.Prev;
      end;
      Inc(J);
    end;
  SetLength(Result, J);
end;
//------------------------------------------------------------------------------

end.