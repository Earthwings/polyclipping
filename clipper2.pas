unit Clipper2;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  3 September 2017                                                *
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
  {$IF CompilerVersion < 15}
    Requires Delphi version 7 or above.
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
  SysUtils, Types, Classes, Math;

type
  cInt = Int64;
  PIntPoint = ^TIntPoint;
  TIntPoint = record X, Y: cInt; end;

  TPath = array of TIntPoint;
  TPaths = array of TPath;

  TIntRect = record Left, Top, Right, Bottom: cInt; end;
  TDoublePoint = record X, Y: Double; end;
  TArrayOfDoublePoint = array of TDoublePoint;

  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);

  //By far the most widely used winding rules for polygon filling are EvenOdd
  //and NonZero (see GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32).
  //https://www.w3.org/TR/SVG/painting.html
  TPolyFillType = (pftEvenOdd, pftNonZero, pftPositive, pftNegative);

  TVertexFlag = (vfOpen, vfOpenStart, vfOpenEnd, vfMaxima, vfMinima);
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
    WindDelta: integer;       //wind direction (ascending: +1; descending: -1)
    WindCnt  : integer;       //edge wind count of
    WindCnt2 : integer;       //wind count of opposite TPolyType
    OutRec   : POutRec;
    Flags    : TActiveFlags;
    //AEL - active edge list (Vatti's AET - active edge table)
    PrevInAEL: PActive;
    NextInAEL: PActive;
    //SEL - 'sorted' edge list (Vatti's ST - sorted table)
    //    -  also (re)used in processing horizontals.
    PrevInSEL: PActive;
    NextInSEL: PActive;
    vertTop  : PVertex;
    LocMin   : PLocalMinimum; //bottom of bound
  end;

  PScanLine = ^TScanLine;
  TScanLine = record
    Y        : cInt;
    Next     : PScanLine;
  end;

  POutPt = ^TOutPt;
  TOutPt = record
    Pt       : TIntPoint;
    Next     : POutPt;
    Prev     : POutPt;
  end;

  TPolyTree = class;
  TPolyPath = class;

  TOutRecFlag = (orOpen, orOuter, orHorz, orHorzJoin);
  TOutRecFlags = set of TOutRecFlag;

  //OutRec: contains a path in the clipping solution. Edges in the AEL will
  //carry a pointer to an OutRec when they are part of the clipping solution.
  TOutRec = record
    Idx      : Integer;
    Owner    : POutRec;
    Pts      : POutPt;
    StartE   : PActive;
    EndE     : PActive;
    Flags    : TOutRecFlags;
    PolyPath : TPolyPath;
  end;

  TDirection = (dRightToLeft, dLeftToRight); //used for horizontal processing

  TClipper2 = class
  private
    FScanLine           : PScanLine;
    FLocMinListSorted   : Boolean;
    FUse64BitRange      : Boolean; //see LoRange and HiRange const below
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
    procedure DisposeOutRec(Index: Integer);
    procedure DisposeAllOutRecs;
    function IsContributing(Edge: PActive): Boolean;
    procedure SetWindingCount(Edge: PActive);
    procedure InsertLocalMinimaIntoAEL(const BotY: cInt);
    procedure DeleteFromAEL(E: PActive);
    procedure AddOutPt(e: PActive; const pt: TIntPoint);
    procedure StartOpenPath(e: PActive; const pt: TIntPoint);
    function SetOwner(e: PActive): POutRec;
    procedure AddLocalMinPoly(e1, e2: PActive; const pt: TIntPoint);
    procedure AddLocalMaxPoly(E1, E2: PActive; const Pt: TIntPoint);
    procedure CopyActivesToSEL;
    procedure UpdateEdgeIntoAEL(var E: PActive);
    procedure SwapOutRecs(E1, E2: PActive);
    procedure IntersectEdges(E1,E2: PActive; Pt: TIntPoint);
    procedure ProcessIntersections(const TopY: cInt);
    procedure DisposeIntersectNodes;
    procedure BuildIntersectList(const TopY: cInt);
    procedure ProcessIntersectList;
    procedure FixupIntersectionOrder;
    procedure SwapPositionsInAEL(E1, E2: PActive);
    procedure SwapPositionsInSEL(E1, E2: PActive);
    procedure ProcessHorizontal(HorzEdge: PActive);
    procedure DoTopOfScanbeam(Y: cInt);
    function DoMaxima(e: PActive): PActive;
    procedure JoinOutrecPaths(E1, E2: PActive);
    procedure BuildResult(out closedPaths, openPaths: TPaths);
    procedure BuildResult2(PolyTree: TPolyTree; out OpenPaths: TPaths);
    procedure PushHorz(E: PActive); {$IFDEF INLINING} inline; {$ENDIF}
    function PopHorz(out E: PActive): Boolean;
    function ExecuteInternal(clipType: TClipType; fillType: TPolyFillType): Boolean;
  protected
    FPolyOutList      : TList;
    FLocMinList       : TList;
    FActives          : PActive; //see AEL above
    FSel              : PActive; //see SEL above
    FVertexList       : TList;
    procedure Reset; virtual;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure CleanUp;
    procedure Clear; virtual;
    function GetBounds: TIntRect;
    procedure AddPath(const path: TPath; polyType: TPolyType = ptSubject;
      isOpen: Boolean = false); virtual;
    procedure AddPaths(const paths: TPaths; polyType: TPolyType = ptSubject;
      isOpen: Boolean = false); virtual;

    function Execute(clipType: TClipType; out ClosedPaths: TPaths;
      fillType: TPolyFillType = pftEvenOdd): Boolean; overload;

    function Execute(clipType: TClipType; out ClosedPaths, OpenPaths: TPaths;
      fillType: TPolyFillType = pftEvenOdd): Boolean; overload;

    function Execute(clipType: TClipType; var Polytree: TPolyTree;
      out OpenPaths: TPaths; fillType: TPolyFillType = pftEvenOdd): Boolean; overload;
  end;

  TPoly = class
  private
    FParent   : TPoly;
    //FIsOpen   : Boolean;
    FPath     : TPath;
    FChilds   : TList;
    function    GetChildCnt: integer;
    function    GetChild(Index: Integer): TPolyPath;
    function    IsHoleNode: boolean;
    property    Parent: TPoly read FParent;
    property    IsHole: Boolean read IsHoleNode;
    //property    IsOpen: Boolean read FIsOpen;
    property    Path: TPath read FPath;
  public
    constructor Create;  virtual;
    destructor  Destroy; override;
    property    ChildCount: Integer read GetChildCnt;
    property    Childs[index: Integer]: TPolyPath read GetChild;
  end;

  TPolyPath = class(TPoly)
  public
    property    Parent;
    property    IsHole;
    //property    IsOpen;
    property    Path;
  end;

  TPolyTree = class(TPoly)
  public
    destructor Destroy; override;
    function AddChild(AParent: TPoly; const Path: TPath): TPolyPath;
    procedure Clear;
  end;

  EClipperLibException = class(Exception);

function Orientation(const path: TPath): Boolean; overload;
function Area(const path: TPath): Double; overload;
function PathContainsPoint(const path: TPath; const pt: TIntPoint): Integer;
function Path1ContainsPath2(const Path1, Path2: TPath): Boolean;
function PolyTreeToPaths(PolyTree: TPolyTree): TPaths;
function GetBounds(const paths: TPaths): TIntRect;

function IntPoint(const X, Y: cInt): TIntPoint; overload;
function IntPoint(const X, Y: Double): TIntPoint; overload;

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
  LoRange: cInt = $B504F333;          //64bit math  (coord range +/- 3.0e+9)
  HiRange: cInt = $3FFFFFFFFFFFFFFF;  //128bit math (coord range +/- 9.2e+18)

  //OVERFLOWCHECKS OFF is a necessary workaround for a Delphi compiler bug that very
  //occasionally reports overflow errors while still returning correct values
  //eg var A, B: Int64; begin A := -$13456780; B := -$73456789; A := A * B; end;
  //see https://forums.embarcadero.com/message.jspa?messageID=871444
  {$OVERFLOWCHECKS OFF}

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
  rsRangeErr        = 'Coordinate exceeds range bounds';
  rsOpenPathSubOnly = 'Only subject paths can be open.';
  rsPolyTreeErr     = 'The TPolyTree parameter hasn''t been assigned.';
  rsClippingErr     = 'Undefined clipping error';

function IsHotEdge(Edge: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := assigned(Edge.OutRec);
end;
//------------------------------------------------------------------------------

function IsStartSide(Edge: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if (Edge = Edge.OutRec.StartE) then
    result := true else
    result := false;
end;
//------------------------------------------------------------------------------

function GetLastOutPt(E: PActive): POutPt; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if IsStartSide(E) then
    result := e.OutRec.Pts else
    result := e.OutRec.Pts.Prev;
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

function UInt64LT(const i, j: Int64): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := UInt64(i) < UInt64(j);
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
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

function PointsEqual(const P1, P2: TIntPoint): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (P1.X = P2.X) and (P1.Y = P2.Y);
end;
//------------------------------------------------------------------------------

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
    Result := EmptyRect;
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

//PathContainsPoint: 0=false; +1=true; -1 when 'pt' is on a polygon edge
function PathContainsPoint(const path: TPath; const pt: TIntPoint): Integer;
var
  i, cnt: Integer;
  d, d2, d3: double; //nb: double not cInt to avoid potential overflow errors
  ip, ipNext: TIntPoint;
begin
  result := 0;
  cnt := Length(path);
  if cnt < 3 then Exit;
  ip := path[0];
  for i := 1 to cnt do
  begin
    if i < cnt then ipNext := path[i]
    else ipNext := path[0];

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
end;
//------------------------------------------------------------------------------

function SlopesEqual(E1, E2: PActive;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
  if UseFullInt64Range then
    Result := Int128Equal(Int128Mul(E1.Top.Y-E1.Bot.Y, E2.Top.X-E2.Bot.X),
      Int128Mul(E1.Top.X-E1.Bot.X, E2.Top.Y-E2.Bot.Y))
  else
    Result := (E1.Top.Y-E1.Bot.Y) * (E2.Top.X-E2.Bot.X) =
      (E1.Top.X-E1.Bot.X) * (E2.Top.Y-E2.Bot.Y);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const Pt1, Pt2, Pt3: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
  if UseFullInt64Range then
    Result := Int128Equal(
      Int128Mul(Pt1.Y-Pt2.Y, Pt2.X-Pt3.X), Int128Mul(Pt1.X-Pt2.X, Pt2.Y-Pt3.Y))
  else
    Result := (Pt1.Y-Pt2.Y)*(Pt2.X-Pt3.X) = (Pt1.X-Pt2.X)*(Pt2.Y-Pt3.Y);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const L1a, L1b, L2a, L2b: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
  if UseFullInt64Range then
    Result := Int128Equal(
      Int128Mul(L1a.Y-L1b.Y, L2a.X-L2b.X), Int128Mul(L2a.Y-L2b.Y, L1a.X-L1b.X))
  else
  //dy1 * dx2 = dy2 * dx1
  Result := (L1a.Y-L1b.Y)*(L2a.X-L2b.X) = (L2a.Y-L2b.Y)*(L1a.X-L1b.X);
end;
//------------------------------------------------------------------------------

(*******************************************************************************
*  Dx:                             0(90deg)                                    *
*                                  |                                           *
*               +inf (180deg) <--- o ---> -inf (0deg)                          *
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
    while assigned(Result) do
    begin
      if Result.vertTop = E.vertTop then Exit;  //Found!
      result := result.NextInAEL;
    end;
    result := nil; //this happens whenever the maxPair is a horizontal
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

procedure TClipper2.CleanUp;
begin
  while assigned(FActives) do DeleteFromAEL(FActives);
  DisposeScanLineList;
  DisposeAllOutRecs;
end;
//------------------------------------------------------------------------------

procedure TClipper2.Clear;
begin
  DisposeLocalMinimaList;
  FCurrentLocMinIdx := 0;
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
  FActives := nil;
  FSel := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper2.InsertScanLine(const Y: cInt);
var
  newSl, sl: PScanLine;
begin
  //The scanline list is a single-linked list of all the Y coordinates of
  //subject and clip vertices in the clipping operation (sorted descending).
  //Only scanlines (Y's) at Local Minima are inserted before clipping starts.
  //As the sweep algorithm progresses, scanlines are removed from this list and
  //new scanlines are inserted when edged becomes active (ie their Top.Y's are
  //inserted). This keeps the list as short as possible and speeds up entry.
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
    else dispose(newSl); //skip/ignore dups
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
      P0IsMinima := p[i].Y < p[0].Y; //p[0].Y == a minima
    end else
    begin
      i := pathLen -1;
      while p[i].Y = p[0].Y do dec(i);
      P0IsMaxima := p[i].Y > p[0].Y; //p[0].Y == a maxima
    end;
  end;

  GetMem(result, sizeof(TVertex) * pathLen);
  result[0].Pt := p[0];
  result[0].flags := [];

  if isOpen then
  begin
    include(result[0].flags, vfOpenStart);
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
    include(result[i].flags, vfOpenEnd);
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
      if P0IsMinima then AddLocMin(@result[0]); //ie just turned to going up
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
  if isOpen then
  begin
    if (PolyType = ptClip) then
      raise EClipperLibException.Create(rsOpenPathSubOnly);
    FHasOpenPaths := true;
  end;
  FLocMinListSorted := false;
  vertices := PathToVertexArray(path, polyType, isOpen);
  if not assigned(vertices) then Exit;
  FVertexList.Add(vertices);
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
    E := FActives; //ie get ready to calc WindCnt2
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
      if IsSamePolyType(E, Edge) or IsOpen(E) then //do nothing
      else if Edge.WindCnt2 = 0 then Edge.WindCnt2 := 1
      else Edge.WindCnt2 := 0;
      E := E.NextInAEL;
    end;
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    while (E <> Edge) do
    begin
      if not IsSamePolyType(E, Edge) and not IsOpen(E) then
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
    if not Assigned(FActives) then
    begin
      Edge.PrevInAEL := nil;
      Edge.NextInAEL := nil;
      FActives := Edge;
    end
    else if not Assigned(StartEdge) and
      E2InsertsBeforeE1(FActives, Edge, preferLeft) then
    begin
      Edge.PrevInAEL := nil;
      Edge.NextInAEL := FActives;
      FActives.PrevInAEL := Edge;
      FActives := Edge;
    end else
    begin
      if not Assigned(StartEdge) then StartEdge := FActives;
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

    if (vfOpenStart in LocMin.vertex.flags) then
    begin
      LeftB := nil;
    end else
    begin
      new(LeftB);
      FillChar(LeftB^, sizeof(TActive), 0);
      LeftB.LocMin := LocMin;
      LeftB.OutRec := nil;
      LeftB.Bot := LocMin.vertex.Pt;
      LeftB.vertTop := LocMin.vertex.prev; //ie descending
      LeftB.Top := LeftB.vertTop.Pt;
      LeftB.Curr := LeftB.Bot;
      LeftB.WindCnt2 := 0;
      LeftB.WindDelta := -1;
      SetDx(LeftB);
      if LocMin.IsOpen then include(LeftB.Flags, afOpen);
    end;

    if (vfOpenEnd in LocMin.vertex.flags) then
    begin
      RightB := nil;
    end else
    begin
      new(RightB);
      FillChar(RightB^, sizeof(TActive), 0);
      RightB.LocMin := LocMin;
      RightB.OutRec := nil;
      RightB.Bot := LocMin.vertex.Pt;
      RightB.vertTop := LocMin.vertex.next; //ie ascending
      RightB.Top := RightB.vertTop.Pt;
      RightB.Curr := RightB.Bot;
      RightB.WindCnt2 := 0;
      RightB.WindDelta := 1;
      SetDx(RightB);
      if LocMin.IsOpen then include(RightB.Flags, afOpen);
    end;

    //Currently LeftB is just the descending bound and RightB is the ascending.
    //Now if the LeftB isn't on the left of RightB then we need swap them.
    if assigned(LeftB) and assigned(RightB) then
    begin
      if (IsHorizontal(LeftB) and (LeftB.Top.X > LeftB.Bot.X)) or
       (not IsHorizontal(LeftB) and (LeftB.Dx < RightB.Dx)) then
       begin
          tmp := LeftB;
          LeftB := RightB;
          RightB := tmp;
       end;
    end
    else if not assigned(LeftB) then
    begin
      LeftB := RightB;
      RightB := nil;
    end;

    InsertEdgeIntoAEL(LeftB, nil, false);      //insert left edge
    SetWindingCount(LeftB);
    contributing := IsContributing(LeftB);

    if assigned(RightB) then
    begin
      RightB.WindCnt := LeftB.WindCnt;
      RightB.WindCnt2 := LeftB.WindCnt2;
      InsertEdgeIntoAEL(RightB, LeftB, false); //insert right edge
      if contributing then
        AddLocalMinPoly(LeftB, RightB, LeftB.Bot);

      if IsHorizontal(RightB) then
        PushHorz(RightB) else
        InsertScanLine(RightB.Top.Y);
    end
    else if IsContributing(LeftB) then
    begin
      //ie open path that's not at a local minima
      StartOpenPath(LeftB, LeftB.Bot);
      AddOutPt(LeftB, LeftB.Bot);
    end;

    if IsHorizontal(LeftB) then
      PushHorz(LeftB) else
      InsertScanLine(LeftB.Top.Y);

    if assigned(RightB) and (LeftB.NextInAEL <> RightB) then
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
    (E <> FActives) then Exit; //already deleted
  if Assigned(AelPrev) then AelPrev.NextInAEL := AelNext
  else FActives := AelNext;
  if Assigned(AelNext) then AelNext.PrevInAEL := AelPrev;
  E.NextInAEL := nil;
  E.PrevInAEL := nil;
  Dispose(E);
end;
//------------------------------------------------------------------------------

procedure TClipper2.StartOpenPath(e: PActive; const pt: TIntPoint);
var
  OutRec: POutRec;
  op    : POutPt;
begin
  new(OutRec);
  OutRec.Idx := FPolyOutList.Add(OutRec);
  OutRec.Owner := nil;
  OutRec.Flags := [orOpen];
  OutRec.PolyPath := nil;
  OutRec.StartE := nil;
  OutRec.EndE := nil;
  e.OutRec := OutRec;
  new(op);
  op.Pt := pt;
  op.Next := op;
  op.Prev := op;
  OutRec.Pts := op;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddOutPt(e: PActive; const pt: TIntPoint);
var
  opStart, opEnd, opNew: POutPt;
  ToStart: Boolean;
begin
  //Outrec.Pts: a circular double-linked-list of POutPt.
  ToStart := IsStartSide(e);
  opStart := e.OutRec.Pts;
  opEnd := opStart.Prev;
  if ToStart then
  begin
    if PointsEqual(pt, opStart.Pt) then Exit;
  end
  else if PointsEqual(pt, opEnd.Pt) then Exit;

  new(opNew);
  opNew.Pt := pt;
  opNew.Next := opStart;
  opNew.Prev := opEnd;
  opEnd.Next := opNew;
  opStart.Prev := opNew;
  if ToStart then
    e.OutRec.Pts := opNew;
end;
//------------------------------------------------------------------------------

procedure EndOutRec(outRec: POutRec); {$IFDEF INLINING} inline; {$ENDIF}
begin
  outRec.StartE.OutRec := nil;
  if assigned(outRec.EndE) then outRec.EndE.OutRec := nil;
  outRec.StartE := nil;
  outRec.EndE := nil;
end;
//------------------------------------------------------------------------------

function TClipper2.SetOwner(e: PActive): POutRec;
begin
  if IsHorizontal(e) and (e.Top.X < e.Bot.X) then
  begin
    e := e.NextInAEL;
    while assigned(e) and (not IsHotEdge(e) or IsOpen(e)) do
      e := e.NextInAEL;
    if not assigned(e) then Result := nil
    else if (orOuter in e.OutRec.Flags) = (e.OutRec.StartE = e) then
      Result := e.OutRec.Owner
    else Result := e.OutRec;
  end else
  begin
    e := e.PrevInAEL;
    while assigned(e) and (not IsHotEdge(e) or IsOpen(e)) do
      e := e.PrevInAEL;
    if not assigned(e) then Result := nil
    else if (orOuter in e.OutRec.Flags) = (e.OutRec.EndE = e) then
      Result := e.OutRec.Owner
    else Result := e.OutRec;
  end;
end;
//------------------------------------------------------------------------------

procedure Clockwise(OutRec: POutRec; e1, e2: PActive); {$IFDEF INLINING} inline; {$ENDIF}
begin
  OutRec.StartE := e1;
  OutRec.EndE := e2;
end;
//------------------------------------------------------------------------------

procedure CounterClockwise(OutRec: POutRec; e1, e2: PActive); {$IFDEF INLINING} inline; {$ENDIF}
begin
  OutRec.StartE := e2;
  OutRec.EndE := e1;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddLocalMinPoly(e1, e2: PActive; const pt: TIntPoint);
var
  OutRec: POutRec;
  op    : POutPt;
begin
  new(OutRec);
  OutRec.Idx := FPolyOutList.Add(OutRec);
  OutRec.Owner := SetOwner(e1);
  if assigned(OutRec.Owner) and (orOuter in OutRec.Owner.Flags) then
    OutRec.Flags := [] else
    OutRec.Flags := [orOuter];
  if afOpen in e1.Flags then Include(OutRec.Flags, orOpen);
  OutRec.PolyPath := nil;

  //now set orientation ...
  if IsHorizontal(e1) then
  begin
    if IsHorizontal(e2) then
    begin
      if (orOuter in OutRec.Flags) = (e1.Bot.X > e2.Bot.X) then
        Clockwise(OutRec, e1,e2) else CounterClockwise(OutRec, e1,e2);
    end
    else if (orOuter in OutRec.Flags) = (e1.Top.X < e1.Bot.X) then
      Clockwise(OutRec, e1,e2) else CounterClockwise(OutRec, e1,e2);
  end
  else if IsHorizontal(e2) then
  begin
    if (orOuter in OutRec.Flags) = (e2.Top.X > e2.Bot.X) then
      Clockwise(OutRec, e1,e2) else CounterClockwise(OutRec, e1,e2);
  end
  else if (orOuter in OutRec.Flags) = (e1.Dx >= e2.Dx) then
    Clockwise(OutRec, e1,e2) else CounterClockwise(OutRec, e1,e2);
  e1.OutRec := OutRec;
  if assigned(e2) then e2.OutRec := OutRec;

  new(op);
  op.Pt := pt;
  op.Next := op;
  op.Prev := op;
  OutRec.Pts := op;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddLocalMaxPoly(E1, E2: PActive; const Pt: TIntPoint);
begin
  AddOutPt(E1, Pt);
  if (E1.OutRec = E2.OutRec) then EndOutRec(E1.OutRec)
  //and to preserve the winding orientation of Outrec ...
  else if e1.OutRec.Idx < e2.OutRec.Idx then
    JoinOutrecPaths(E1, E2) else
    JoinOutrecPaths(E2, E1);
end;
//------------------------------------------------------------------------------

procedure TClipper2.CopyActivesToSEL;
var
  E: PActive;
begin
  FSel := FActives;
  E := FActives;
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

procedure TClipper2.PushHorz(E: PActive);
begin
  if assigned(FSel) then
    E.NextInSEL := FSel else
    E.NextInSEL := nil;
  FSel := E;
end;
//------------------------------------------------------------------------------

function TClipper2.PopHorz(out E: PActive): Boolean;
begin
  result := assigned(FSel);
  if not result then Exit;
  E := FSel;
  FSel := FSel.NextInSEL;
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
    e := or1.StartE;
    or1.StartE := or1.EndE;
    or1.EndE := e;
    Exit;
  end;
  if assigned(or1) then
  begin
    if E1 = or1.StartE then
      or1.StartE := E2 else
      or1.EndE := E2;
  end;
  if assigned(or2) then
  begin
    if E2 = or2.StartE then
      or2.StartE := E1 else
      or2.EndE := E1;
  end;
  E1.OutRec := or2;
  E2.OutRec := or1;
end;
//------------------------------------------------------------------------------

procedure TerminateOpenEdge(E: PActive);
begin
  if E.OutRec.StartE = E then
    E.OutRec.StartE := nil else
    E.OutRec.EndE := nil;
  E.OutRec := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper2.IntersectEdges(E1, E2: PActive; Pt: TIntPoint);
var
  E1Contributing, E2contributing: Boolean;
  E1Wc, E2Wc, E1Wc2, E2Wc2: Integer;
begin
  //E1 will be to the left of E2 BELOW the intersection. Therefore E1 is before
  //E2 in AEL except when E1 is being inserted at the intersection point ...

  E1Contributing := IsHotEdge(E1);
  E2contributing := IsHotEdge(E2);

  E1.Curr := Pt;
  E2.Curr := Pt;

  //if either edge is on an OPEN path ...
  if FHasOpenPaths and (IsOpen(E1) or IsOpen(E2)) then
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
          if not E1contributing then StartOpenPath(E1, Pt);
          AddOutPt(E1, pt);
          if (E1Contributing) then TerminateOpenEdge(E1);
        end;
      end else
      begin
        if (E1Contributing) then
        begin
          if not E2contributing then StartOpenPath(E2, Pt);
          AddOutPt(E2, pt);
          if (E2Contributing) then TerminateOpenEdge(E2);
        end;
      end;
    end
    else if not IsSamePolyType(E1, E2) then
    begin
      //toggle subj open path OutIdx on/off when Abs(clip.WndCnt) = 1 ...
      if IsOpen(E1) and (Abs(E2.WindCnt) = 1) and
       ((FClipType <> ctUnion) or (E2.WindCnt2 = 0)) then
      begin
        if not E1contributing then StartOpenPath(E1, Pt);
        AddOutPt(E1, Pt);
        if E1Contributing then TerminateOpenEdge(E1);
      end
      else if IsOpen(E2) and (Abs(E1.WindCnt) = 1) and
       ((FClipType <> ctUnion) or (E1.WindCnt2 = 0)) then
      begin
        if not E2contributing then StartOpenPath(E2, Pt);
        AddOutPt(E2, Pt);
        if E2Contributing then TerminateOpenEdge(E2);
      end
    end;
    Exit;
  end;

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
    end
    else if (E1.OutRec = E2.OutRec) then //optional
    begin
      AddLocalMaxPoly(E1, E2, Pt);
      AddLocalMinPoly(E1, E2, Pt);
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

function TClipper2.ExecuteInternal(clipType: TClipType; fillType: TPolyFillType): Boolean;
var
  Y: cInt;
  E: PActive;
begin
  Result := False;
  if FExecuteLocked then Exit;
  try try
    FExecuteLocked := True;
    FFillType := fillType;
    FClipType := clipType;
    Reset;
    if not PopScanLine(Y) then Exit;

    ////////////////////////////////////////////////////////
    while true do
    begin
      InsertLocalMinimaIntoAEL(Y);
      while PopHorz(E) do ProcessHorizontal(E);
      if not PopScanLine(Y) then break; //Y == top of scanbeam
      ProcessIntersections(Y);          //process scanbeam intersections
      DoTopOfScanbeam(Y); //leaves pending horizontals for next loop iteration
    end;
    ////////////////////////////////////////////////////////
    Result := True;
  except;
    Result := False;
  end;
  finally
    FExecuteLocked := False;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.Execute(clipType: TClipType; out ClosedPaths: TPaths;
  fillType: TPolyFillType): Boolean;
var
  dummy: TPaths;
begin
  ClosedPaths := nil;
  try
    Result := ExecuteInternal(clipType, fillType);
    if Result then BuildResult(ClosedPaths, dummy);
  finally
    CleanUp;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.Execute(clipType: TClipType; out ClosedPaths, OpenPaths: TPaths;
  fillType: TPolyFillType = pftEvenOdd): Boolean;
begin
  ClosedPaths := nil;
  OpenPaths := nil;
  try
    Result := ExecuteInternal(clipType, fillType);
    if Result then BuildResult(ClosedPaths, OpenPaths);
  finally
    CleanUp;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.Execute(clipType: TClipType; var Polytree: TPolyTree;
  out OpenPaths: TPaths; fillType: TPolyFillType): Boolean;
begin
  if not assigned(Polytree) then
    raise EClipperLibException.Create(rsPolyTreeErr);
  Polytree.Clear;
  OpenPaths := nil;
  try
    Result := ExecuteInternal(clipType, fillType);
    if Result then BuildResult2(Polytree, OpenPaths);
  finally
    CleanUp;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessIntersections(const TopY: cInt);
begin
  try
    BuildIntersectList(TopY);
    if (FIntersectList.Count = 0) then Exit;
    FixupIntersectionOrder;
    ProcessIntersectList;
  finally
    DisposeIntersectNodes; //clean up if there's been an error
    FSel := nil;
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
  if not Assigned(FActives) then Exit;

  //copy AEL to SEL while also adjusting Curr.X ...
  FSel := FActives;
  E := FActives;
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
    E := FSel;
    while Assigned(E.NextInSEL) do
    begin
      eNext := E.NextInSEL;
      if (E.Curr.X > eNext.Curr.X) then
      begin
        //An intersection is occuring somewhere within the scanbeam ...
        pt := GetIntersectPoint(E, eNext);

        //Rounding errors can occasionally place the calculated intersection
        //point either below or above the scanbeam, so check and correct ...
        if (pt.Y > E.Curr.Y) then
        begin
          pt.Y := E.Curr.Y;      //E.Curr.Y is still the bottom of scanbeam
          //use the more vertical of the 2 edges to derive pt.X ...
          if (abs(E.Dx) < abs(eNext.Dx)) then
            pt.X := TopX(E, pt.Y) else
            pt.X := TopX(eNext, pt.Y);
        end
        else if pt.Y < TopY then
        begin
          pt.Y := TopY;          //TopY = top of scanbeam
          if E.Top.Y = TopY then
            pt.X := E.Top.X
          else if eNext.Top.Y = TopY then
            pt.X := eNext.Top.X
          else if (abs(E.Dx) < abs(eNext.Dx)) then
            pt.X := E.Curr.X
          else
            pt.X := eNext.Curr.X;
        end;

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

procedure TClipper2.FixupIntersectionOrder;
var
  I, J, Cnt: Integer;
  Node: PIntersectNode;
begin
  //Intersections have been sorted so the bottom-most are processed first but
  //it's also crucial that intersections are made between adjacent edges, so
  //the order of these intersections may need some adjusting ...
  Cnt := FIntersectList.Count;
  if Cnt < 2 then exit;

  CopyActivesToSEL;
  FIntersectList.Sort(IntersectListSort);
  for I := 0 to Cnt - 1 do
  begin
    if not EdgesAdjacent(FIntersectList[I]) then
    begin
      J := I + 1;
      while (J < Cnt) and not EdgesAdjacent(FIntersectList[J]) do inc(J);
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
    if not Assigned(E2.PrevInAEL) then FActives := E2;
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
    if not Assigned(E1.PrevInAEL) then FActives := E1;
  end else
    raise EClipperLibException.Create(rsClippingErr);
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
    if not Assigned(E2.PrevInSEL) then FSel := E2;
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
    if not Assigned(E1.PrevInSEL) then FSel := E1;
  end else
    raise EClipperLibException.Create(rsClippingErr);
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessHorizontal(HorzEdge: PActive);
var
  e, eNext, maxPair: PActive;
  horzLeft, horzRight: cInt;
  direction: TDirection;
  pt: TIntPoint;
  isMaxima: Boolean;

  procedure ResetHorzDirection;
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
* eg: 3 horizontals at a scanline:  /   |                     /          /     *
*              |                   /    |    (HE3) o=========%==========o      *
*              o=======o (HE2)    /     |         /         /                  *
*         o============#=========*======*========#=========o (HE1)             *
*        /             |        /       |       /                              *
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

  maxPair := nil;
  if (vfMaxima in HorzEdge.vertTop.flags) then
  begin
    if (afOpen in HorzEdge.flags) and
      ([vfOpenStart, vfOpenEnd] * HorzEdge.vertTop.flags <> []) then
    begin
      SetMaximaFlag(HorzEdge);
    end else
    begin
      maxPair := GetMaximaPair(HorzEdge);
      if assigned(maxPair) then
      begin
        SetMaximaFlag(HorzEdge);
        SetMaximaFlag(maxPair);
      end;
    end;
  end;

  ResetHorzDirection;
  if IsHotEdge(HorzEdge) then
    AddOutPt(HorzEdge, HorzEdge.Curr);

  while true do //loops through consec. horizontal edges (if open)
  begin
    isMaxima := vfMaxima in HorzEdge.vertTop.flags;
    if direction = dRightToLeft then
      e := HorzEdge.PrevInAEL else
      e := HorzEdge.NextInAEL;

    while assigned(e) do
    begin
      //break if we've gone past the end of the horizontal ...
      if ((direction = dLeftToRight) and (e.Curr.X > horzRight)) or
        ((direction = dRightToLeft) and (e.Curr.X < horzLeft)) then break;
      //or if we've got to the end of an intermediate horizontal edge ...
      if (E.Curr.X = HorzEdge.Top.X) and not isMaxima and not IsHorizontal(e) then
      begin
        pt := NextVertex(HorzEdge).Pt;
        if((direction = dLeftToRight) and (TopX(E, pt.Y) >= pt.X)) or
          ((direction = dRightToLeft) and (TopX(E, pt.Y) <= pt.X)) then Break;
      end;

      if (e = maxPair) then
      begin
        if IsHotEdge(HorzEdge)  then
          AddLocalMaxPoly(HorzEdge, e, HorzEdge.Top);
        DeleteFromAEL(e);
        DeleteFromAEL(HorzEdge);
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
    ResetHorzDirection;
  end;

  if IsHotEdge(HorzEdge) then
    AddOutPt(HorzEdge, HorzEdge.Top);

  //unless its an open path we've reached the end of an intermediate horiz ...

  if IsMaximaFlagged(HorzEdge) and not assigned(maxPair) then
    DeleteFromAEL(HorzEdge) //ie an open path
  else
    UpdateEdgeIntoAEL(HorzEdge);
end;
//------------------------------------------------------------------------------

procedure TClipper2.DoTopOfScanbeam(Y: cInt);
var
  e: PActive;
begin
  e := FActives;
  while Assigned(e) do
  begin
    E.Flags := E.Flags - [afMaxima];
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
        if IsHotEdge(e) then AddOutPt(e, e.Bot);
        if IsHorizontal(e) then
          PushHorz(e); //horizontals are processed later
      end;
    end else
    begin
      e.Curr.Y := Y;
      e.Curr.X := TopX(e, Y);
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

  if (afOpen in e.Flags) and
    ([vfOpenStart, vfOpenEnd] * e.vertTop.flags <> []) then
  begin
    Result := e.NextInAEL;
    if IsHotEdge(e) then AddOutPt(e, e.Top);
    if not IsHorizontal(e) then DeleteFromAEL(e);
    Exit;
  end else
  begin
    eMaxPair := GetMaximaPair(e);
    if not assigned(eMaxPair) then
    begin
      //EMaxPair is a horizontal ...
      Result := e.NextInAEL;
      Exit;
    end;
  end;

  //only non-horizontal maxima here.
  eNext := e.NextInAEL;

  //process any edges between maxima pair ...
  while (eNext <> eMaxPair) do
  begin
    IntersectEdges(e, eNext, e.Top);
    SwapPositionsInAEL(e, eNext);
    eNext := e.NextInAEL;
  end;

  if IsOpen(e) then
  begin
    if IsHotEdge(e) then
    begin
      if assigned(eMaxPair) then
        AddLocalMaxPoly(e, eMaxPair, e.Top) else
        AddOutPt(e, e.Top);
    end;
    if assigned(eMaxPair) then
      DeleteFromAEL(eMaxPair);
    DeleteFromAEL(e);

    if assigned(ePrev) then
      Result := ePrev.NextInAEL else
      Result := FActives;
    Exit;
  end;

  //here E.NextInAEL == ENext == EMaxPair ...
  if IsHotEdge(e) then
      AddLocalMaxPoly(e, eMaxPair, e.Top);

  DeleteFromAEL(e);
  DeleteFromAEL(eMaxPair);
  if assigned(ePrev) then
    Result := ePrev.NextInAEL else
    Result := FActives;
end;
//------------------------------------------------------------------------------

procedure ReversePolyPtLinks(PP: POutPt); {$IFDEF INLINING} inline; {$ENDIF}
var
  Pp1,Pp2: POutPt;
begin
  if (PP.Next = PP.Prev) then Exit;
  Pp1 := PP;
  repeat
    Pp2:= Pp1.Next;
    Pp1.Next := Pp1.Prev;
    Pp1.Prev := Pp2;
    Pp1 := Pp2;
  until Pp1 = PP;
end;
//------------------------------------------------------------------------------

procedure TClipper2.JoinOutrecPaths(E1, E2: PActive);
var
  P1_st, P1_end, P2_st, P2_end: POutPt;
begin
  //join E2 outrec path onto E1 outrec path and then delete E2 outrec path
  //pointers. (nb: Only very rarely do the joining ends share the same coords.)
  P1_st :=  E1.OutRec.Pts;
  P2_st :=  E2.OutRec.Pts;
  P1_end := P1_st.Prev;
  P2_end := P2_st.Prev;
  if IsStartSide(E1) then
  begin
    if IsStartSide(E2) then
    begin
      //start-start join
      ReversePolyPtLinks(P2_st);
      P2_st.Next := P1_st;
      P1_st.Prev := P2_st;
      P1_end.Next := P2_end; //P2 now reversed
      P2_end.Prev := P1_end;
      E1.OutRec.Pts := P2_end;
      E1.OutRec.StartE := E2.OutRec.EndE;
    end else
    begin
      //end-start join
      P2_end.Next := P1_st;
      P1_st.Prev := P2_end;
      P2_st.Prev := P1_end;
      P1_end.Next := P2_st;
      E1.OutRec.Pts := P2_st;
      E1.OutRec.StartE := E2.OutRec.StartE;
    end;
    if assigned(E1.OutRec.StartE) then //ie closed path
      E1.OutRec.StartE.OutRec := E1.OutRec;
  end else
  begin
    if IsStartSide(E2) then
    begin
      //end-start join (see JoinOutrec3.png)
      P1_end.Next := P2_st;
      P2_st.Prev := P1_end;
      P1_st.Prev := P2_end;
      P2_end.Next := P1_st;
      E1.OutRec.EndE := E2.OutRec.EndE;
    end else
    begin
      //end-end join (see JoinOutrec4.png)
      ReversePolyPtLinks(P2_st);
      P1_end.Next := P2_end; //P2 now reversed
      P2_end.Prev := P1_end;
      P2_st.Next := P1_st;
      P1_st.Prev := P2_st;
      E1.OutRec.EndE := E2.OutRec.StartE;
    end;
    if assigned(E1.OutRec.EndE) then //ie closed path
      E1.OutRec.EndE.OutRec := E1.OutRec;
  end;

  if E1.OutRec.Owner = E2.OutRec then
    raise EClipperLibException.Create(rsClippingErr);

  //after joining, the E2.OutRec contains not vertices ...
  E2.OutRec.StartE := nil;
  E2.OutRec.EndE := nil;
  E2.OutRec.Pts := nil;
  E2.OutRec.Owner := E1.OutRec; //this may be redundant

  //and e1 and e2 are maxima and are about to be dropped from the Actives list.
  e1.OutRec := nil;
  e2.OutRec := nil;
end;
//------------------------------------------------------------------------------

function PointCount(Pts: POutPt): Integer; {$IFDEF INLINING} inline; {$ENDIF}
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

procedure TClipper2.BuildResult(out closedPaths, openPaths: TPaths);
var
  I, J, cnt, cntClosed, cntOpen: Integer;
  OutRec: POutRec;
  Op: POutPt;
begin
  cntClosed := 0;
  cntOpen := 0;
  SetLength(closedPaths, FPolyOutList.Count);
  SetLength(openPaths, FPolyOutList.Count);
  for I := 0 to FPolyOutList.Count -1 do
    if Assigned(fPolyOutList[I]) then
    begin
      OutRec := FPolyOutList[I];
      if not assigned(OutRec.Pts) then Continue;

      Op := OutRec.Pts.Prev;
      cnt := PointCount(Op);
      //fixup for duplicate start and end points ...
      if PointsEqual(Op.Pt, OutRec.Pts.Pt) then dec(cnt);

      if (orOpen in OutRec.Flags) then
      begin
        if (Cnt < 1) then Continue;
        SetLength(openPaths[cntOpen], cnt);
        for J := 0 to cnt -1 do
        begin
          openPaths[cntOpen][J] := Op.Pt;
          Op := Op.Prev;
        end;
        Inc(cntOpen);
      end else
      begin
        if (Cnt < 2) then Continue;
        SetLength(closedPaths[cntClosed], cnt);
        for J := 0 to cnt -1 do
        begin
          closedPaths[cntClosed][J] := Op.Pt;
          Op := Op.Prev;
        end;
        Inc(cntClosed);
      end;

    end;
  SetLength(closedPaths, cntClosed);
  SetLength(openPaths, cntOpen);
end;
//------------------------------------------------------------------------------

procedure TClipper2.BuildResult2(PolyTree: TPolyTree; out OpenPaths: TPaths);
var
  i, j, cnt, OpenCnt: Integer;
  OutRec: POutRec;
  Op: POutPt;
  path: TPath;
  parentPoly: TPoly;
begin
  setLength(OpenPaths, FPolyOutList.Count);
  OpenCnt := 0;
  for i := 0 to FPolyOutList.Count -1 do
    if Assigned(fPolyOutList[i]) then
    begin
      OutRec := FPolyOutList[i];
      if not assigned(OutRec.Pts) then Continue;

      Op := OutRec.Pts.Prev;
      cnt := PointCount(Op);
      //avoid duplicate start and end points ...
      if PointsEqual(Op.Pt, OutRec.Pts.Pt) then dec(cnt);

      if (cnt < 2) then
      begin
        if not (orOpen in OutRec.Flags) or (cnt < 1) then Continue;
      end;

      SetLength(path, cnt);
      for j := 0 to cnt -1 do
      begin
        path[j] := Op.Pt;
        Op := Op.Prev;
      end;

      if orOpen in OutRec.Flags then
      begin
        OpenPaths[OpenCnt] := path;
        inc(OpenCnt);
      end else
      begin
        if assigned(OutRec.Owner) then parentPoly := OutRec.Owner.PolyPath
        else parentPoly := PolyTree;
        OutRec.PolyPath := PolyTree.AddChild(parentPoly, path);
      end;
    end;
  setLength(OpenPaths, OpenCnt);
end;

//------------------------------------------------------------------------------
//  TPoly class
//------------------------------------------------------------------------------

constructor TPoly.Create;
begin
  FChilds := TList.Create;
end;
//------------------------------------------------------------------------------

destructor TPoly.Destroy;
var
  i: integer;
begin
  for i := 0 to FChilds.Count -1 do
    TPoly(FChilds[i]).Free;
  FChilds.Free;
  inherited Destroy;
end;
//------------------------------------------------------------------------------

function  TPoly.GetChild(Index: Integer): TPolyPath;
begin
  if (Index < 0) or (index >= FChilds.Count) then
    REsult := nil else
    Result := TPolyPath(FChilds[Index]);
end;
//------------------------------------------------------------------------------

function  TPoly.IsHoleNode: boolean;
begin
  result := not assigned(FParent) or not FParent.IsHoleNode;
end;
//------------------------------------------------------------------------------

function  TPoly.GetChildCnt: integer;
begin
  Result := FChilds.Count;
end;

//------------------------------------------------------------------------------
// TPolyTree class
//------------------------------------------------------------------------------

destructor TPolyTree.Destroy;
begin
  Clear;
  inherited;
end;
//------------------------------------------------------------------------------

function TPolyTree.AddChild(AParent: TPoly;
  const Path: TPath): TPolyPath;
begin
  assert((AParent is TPolyTree) or
    Path1ContainsPath2(AParent.Path, Path), 'oops!');
  Result := TPolyPath.Create;
  Result.FPath := Path;
  //Result.FIsOpen := IsOpen;
  //if IsOpen then AParent := self;
  AParent.FChilds.Add(Result);
  Result.FParent := AParent;
end;
//------------------------------------------------------------------------------

procedure TPolyTree.Clear;
var
  i: integer;
begin
  for i := 0 to FChilds.Count -1 do
    TPoly(FChilds[i]).Free;
  FChilds.Clear;
end;
//------------------------------------------------------------------------------

procedure AddPolyNodeToPaths(Poly: TPoly; var Paths: TPaths);
var
  I: Integer;
begin
  if (Length(Poly.Path) > 0) then
  begin
    I := Length(Paths);
    SetLength(Paths, I +1);
    Paths[I] := Poly.Path;
  end;

  for I := 0 to Poly.ChildCount - 1 do
    AddPolyNodeToPaths(Poly.Childs[I], Paths);
end;
//------------------------------------------------------------------------------

function PolyTreeToPaths(PolyTree: TPolyTree): TPaths;
begin
  Result := nil;
  AddPolyNodeToPaths(PolyTree, Result);
end;
//------------------------------------------------------------------------------

function Path1ContainsPath2(const Path1, Path2: TPath): Boolean;
var
  i: integer;
  pt: TIntPoint;
begin
  //precondition: Path2 may touch but not intersect Path1.
  result := false;
  if (length(Path1) < 3) or (length(Path2) = 0) then Exit;
  for i := 0 to high(Path2) do
  begin
    pt := Path2[i];
    //nb: PathContainsPoint returns 0 if false, +1 if true, -1 if pt on polygon
    case PathContainsPoint(Path1, pt) of
      0: Exit;
      1: begin Result := true; Exit; end;
      //else point on line
    end;
  end;
  result := true; //ie no vertex in Path2 is outside Path1.
end;
//---------------------------------------------------------------------------

end.

