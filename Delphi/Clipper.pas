unit Clipper;

(*******************************************************************************
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (beta)                                                     *
* Date      :  11 Noveber 2017                                                 *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
* Purpose   :  Base clipping module                                            *
* License   :  http://www.boost.org/LICENSE_1_0.txt                            *
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
  SysUtils, Classes, Math;

type
  TPoint64 = record X, Y: Int64; end;

  TPath = array of TPoint64;
  TPaths = array of TPath;

  TRect64 = record Left, Top, Right, Bottom: Int64; end;

  TClipType = (ctNone, ctIntersection, ctUnion, ctDifference, ctXor);
  TPathType = (ptSubject, ptClip);
  //By far the most widely used winding rules for polygon filling are EvenOdd
  //and NonZero (see GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32).
  //https://www.w3.org/TR/SVG/painting.html
  TFillRule = (frEvenOdd, frNonZero, frPositive, frNegative);

  TVertexFlag = (vfOpenStart, vfOpenEnd, vfLocMax, vfLocMin);
  TVertexFlags = set of TVertexFlag;

  PVertex = ^TVertex;
  TVertex = record
    Pt    : TPoint64;
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

  PLocalMinima = ^TLocalMinima;
  TLocalMinima = record
    vertex    : PVertex;
    PolyType  : TPathType;
    IsOpen    : Boolean;
  end;

  TOutRec = class;

  PActive = ^TActive;
  TActive = record
    Bot      : TPoint64;
    Curr     : TPoint64;
    Top      : TPoint64;
    Dx       : Double;        //inverse of edge slope (zero = vertical)
    WindDx   : Integer;       //wind direction (ascending: +1; descending: -1)
    WindCnt  : Integer;       //current wind count
    WindCnt2 : Integer;       //current wind count of opposite TPolyType
    OutRec   : TOutRec;
    //AEL - active edge list (Vatti's AET - active edge table)
    PrevInAEL: PActive;
    NextInAEL: PActive;
    //SEL - 'sorted' edge list (Vatti's ST - sorted table)
    //    -  also (re)used in processing horizontals.
    PrevInSEL: PActive;
    NextInSEL: PActive;
    MergeJump: PActive;
    VertTop  : PVertex;
    LocMin   : PLocalMinima; //bottom of bound
  end;

  PScanLine = ^TScanLine;
  TScanLine = record
    Y        : Int64;
    Next     : PScanLine;
  end;

  TPolyTree = class;
  TPolyPath = class;

  TOutPt = class
    Pt       : TPoint64;
    Next     : TOutPt;
    Prev     : TOutPt;
  end;

  TOutRecFlag = (orInner, orOuter, orOpen);

  //OutRec: contains a path in the clipping solution. Edges in the AEL will
  //carry a pointer to an OutRec when they are part of the clipping solution.
  TOutRec = class
    Idx      : Integer;
    Owner    : TOutRec;
    startE   : PActive;
    endE     : PActive;
    Pts      : TOutPt;
    PolyPath : TPolyPath;
    Flag     : TOutRecFlag;
  end;

  TClipper = class
  private
    FScanLine           : PScanLine;
    FLocMinListSorted   : Boolean;
    FHasOpenPaths       : Boolean;
    FCurrentLocMinIdx   : Integer;
    FIntersectList      : TList;
    FClipType           : TClipType;
    FFillRule           : TFillRule;
    FOutRecList         : TList;
    FLocMinList         : TList;
    FVertexList         : TList;
    FActives            : PActive; //see AEL above
    FSel                : PActive; //see SEL above
    procedure Reset;
    procedure InsertScanLine(const Y: Int64);
    function PopScanLine(out Y: Int64): Boolean;
    function PopLocalMinima(Y: Int64;
      out localMinima: PLocalMinima): Boolean;
    procedure DisposeScanLineList;
    procedure DisposeOutRec(index: Integer);
    procedure DisposeAllOutRecs;
    procedure DisposeVerticesAndLocalMinima;
    procedure AddPathToVertexList(const p: TPath;
      polyType: TPathType; isOpen: Boolean);
    function IsContributingClosed(e: PActive): Boolean;
    function IsContributingOpen(e: PActive): Boolean;
    procedure SetWindingLeftEdgeClosed(e: PActive);
    procedure SetWindingLeftEdgeOpen(e: PActive);
    procedure InsertLocalMinimaIntoAEL(const botY: Int64);
    procedure PushHorz(e: PActive); {$IFDEF INLINING} inline; {$ENDIF}
    function PopHorz(out e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
    procedure JoinOutrecPaths(e1, e2: PActive);
    procedure StartOpenPath(e: PActive; const pt: TPoint64);
    procedure UpdateEdgeIntoAEL(var e: PActive);
    procedure IntersectEdges(e1, e2: PActive; pt: TPoint64);
    procedure DeleteFromAEL(e: PActive);
    procedure CopyActivesToSEL; {$IFDEF INLINING} inline; {$ENDIF}
    procedure CopyActivesToSELAdjustCurrX(topY: Int64);
    procedure ProcessIntersections(const topY: Int64);
    procedure DisposeIntersectNodes;
    procedure InsertNewIntersectNode(e1, e2: PActive; topY: Int64);
    procedure BuildIntersectList(const topY: Int64);
    procedure ProcessIntersectList;
    procedure FixupIntersectionOrder;
    procedure SwapPositionsInAEL(e1, e2: PActive);
    procedure SwapPositionsInSEL(e1, e2: PActive);
    procedure Insert2Before1InSel(first, second: PActive);
      {$IFDEF INLINING} inline; {$ENDIF}
    procedure ProcessHorizontal(horzEdge: PActive);
    procedure DoTopOfScanbeam(Y: Int64);
    function DoMaxima(e: PActive): PActive;
    procedure BuildResult(out closedPaths, openPaths: TPaths);
    procedure BuildResult2(polyTree: TPolyTree; out openPaths: TPaths);
  protected
    procedure CleanUp;
    function CreateOutPt: TOutPt; virtual;
    function CreateOutRec: TOutRec; virtual;
    function AddOutPt(e: PActive; const pt: TPoint64): TOutPt; virtual;
    procedure AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64); virtual;
    procedure AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64); virtual;
    function ExecuteInternal(clipType: TClipType; fillRule: TFillRule): Boolean;
    property OutRecList: TList read FOutRecList;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Clear;
    function GetBounds: TRect64;
    procedure AddPath(const path: TPath; polyType: TPathType = ptSubject;
      isOpen: Boolean = false); virtual;
    procedure AddPaths(const paths: TPaths; polyType: TPathType = ptSubject;
      isOpen: Boolean = false); virtual;
    function Execute(clipType: TClipType; out closedPaths: TPaths;
      fillRule: TFillRule = frEvenOdd): Boolean; overload; virtual;
    function Execute(clipType: TClipType; out closedPaths, openPaths: TPaths;
      fillRule: TFillRule = frEvenOdd): Boolean; overload; virtual;
    function Execute(clipType: TClipType;
      var polytree: TPolyTree; out openPaths: TPaths;
      fillRule: TFillRule = frEvenOdd): Boolean; overload; virtual;
  end;

  TPolyPath = class
  private
    FParent    : TPolyPath;
    FPath      : TPath;
    FChildList : TList;
    function     GetChildCnt: Integer;
    function     GetChild(index: Integer): TPolyPath;
    function     IsHoleNode: Boolean;
  public
    constructor  Create;  virtual;
    destructor   Destroy; override;
    procedure    Clear;
    function     AddChild(const path: TPath): TPolyPath;
    property     Parent: TPolyPath read FParent;
    property     IsHole: Boolean read IsHoleNode;
    property     Path: TPath read FPath;
    property     ChildCount: Integer read GetChildCnt;
    property     Child[index: Integer]: TPolyPath read GetChild;
  end;

  TPolyTree = class(TPolyPath);

  EClipperLibException = class(Exception);

function PointsEqual(const p1, p2: TPoint64): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
function Point64(const X, Y: Int64): TPoint64; overload;
  {$IFDEF INLINING} inline; {$ENDIF}
function Point64(const X, Y: Double): TPoint64; overload;
  {$IFDEF INLINING} inline; {$ENDIF}
function Rect64(const left, top, right, bottom: Int64): TRect64;

implementation

//OVERFLOWCHECKS OFF is a necessary workaround for a Delphi compiler bug that very
//occasionally reports overflow errors while still returning correct values
//eg var A, B: Int64; begin A := -$13456780; B := -$73456789; A := A * B; end;
//see https://forums.embarcadero.com/message.jspa?messageID=871444
//nb: this issue was resolved in Delphi 10.2
{$OVERFLOWCHECKS OFF}

const
  HORIZONTAL = NegInfinity;

type
  PIntersectNode = ^TIntersectNode;
  TIntersectNode = record
    Edge1  : PActive;
    Edge2  : PActive;
    Pt     : TPoint64;
  end;

resourcestring
  rsOpenPathSubOnly = 'Only subject paths can be open.';
  rsPolyTreeErr     = 'The TPolyTree parameter hasn''t been assigned.';
  rsClippingErr     = 'Undefined clipping error';

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

function IsHotEdge(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := assigned(e.OutRec);
end;
//------------------------------------------------------------------------------

function IsOpen(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := e.LocMin.IsOpen;
end;
//------------------------------------------------------------------------------

function IsStartSide(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (e = e.OutRec.startE);
end;
//------------------------------------------------------------------------------

procedure SwapSides(outRec: TOutRec); {$IFDEF INLINING} inline; {$ENDIF}
var
  e2: PActive;
begin
  e2 := outRec.startE;
  outRec.startE := outRec.endE;
  outRec.endE := e2;
  outRec.Pts := outRec.Pts.Next;
end;
//------------------------------------------------------------------------------

function FixOrientation(e: PActive): Boolean;
var
  e2: PActive;
begin
  result := true;
  e2 := e;
  while assigned(e2.PrevInAEL) do
  begin
    e2 := e2.PrevInAEL;
    if assigned(e2.OutRec) and not IsOpen(e2) then result := not result;
  end;
  if result <> IsStartSide(e) then
  begin
    if result then e.OutRec.Flag := orOuter
    else e.OutRec.Flag := orInner;
    SwapSides(e.OutRec);
    Result := true; //all fixed
  end
  else result := false; //no fix needed
end;
//------------------------------------------------------------------------------

function TopX(e: PActive; const currentY: Int64): Int64;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if currentY = e.Top.Y then Result := e.Top.X
  else if e.Top.X = e.Bot.X then Result := e.Bot.X
  else Result := e.Bot.X + Round(e.Dx*(currentY - e.Bot.Y));
end;
//------------------------------------------------------------------------------

function IsHorizontal(e: PActive): Boolean;
begin
  Result := e.Dx = HORIZONTAL;
end;
//------------------------------------------------------------------------------

function PointsEqual(const p1, p2: TPoint64): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (p1.X = p2.X) and (p1.Y = p2.Y);
end;
//------------------------------------------------------------------------------

function Point64(const X, Y: Int64): TPoint64;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function Point64(const X, Y: Double): TPoint64;
begin
  Result.X := Round(X);
  Result.Y := Round(Y);
end;
//------------------------------------------------------------------------------

function Rect64(const left, top, right, bottom: Int64): TRect64;
begin
  Result.Left := left;
  Result.Top := top;
  Result.Right := right;
  Result.Bottom := bottom;
end;
//------------------------------------------------------------------------------

function GetTopDeltaX(e1, e2: PActive): Int64; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if e1.Top.Y > e2.Top.Y then
    Result := TopX(e2, e1.Top.Y) - e1.Top.X else
    Result := e2.Top.X - TopX(e1, e2.Top.Y);
end;
//------------------------------------------------------------------------------

procedure SwapActives(var e1, e2: PActive); {$IFDEF INLINING} inline; {$ENDIF}
var
  e: PActive;
begin
  e := e1; e1 := e2; e2 := e;
end;
//------------------------------------------------------------------------------

procedure MoveEdgeToFollowLeftInAEL(e, eLeft: PActive);
var
  aelPrev, aelNext: PActive;
begin
  //extract first ...
  aelPrev := e.PrevInAEL;
  aelNext := e.NextInAEL;
  aelPrev.NextInAEL := aelNext;
  if Assigned(aelNext) then aelNext.PrevInAEL := aelPrev;
  //now reinsert ...
  e.NextInAEL := eLeft.NextInAEL;
  eLeft.NextInAEL.PrevInAEL := e;
  e.PrevInAEL := eLeft;
  eLeft.NextInAEL := e;
end;
//------------------------------------------------------------------------------

function E2InsertsBeforeE1(e1, e2: PActive; preferLeft: Boolean): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if preferLeft then
  begin
    if e2.Curr.X = e1.Curr.X then
      result := GetTopDeltaX(e1, e2) < 0 else
      Result := e2.Curr.X < e1.Curr.X;
  end
  else if e2.Curr.X = e1.Curr.X then
    result := GetTopDeltaX(e1, e2) <= 0
  else
    Result := e2.Curr.X <= e1.Curr.X;    //note ' <= ' when not preferLeft
end;
//----------------------------------------------------------------------

function GetPolyType(const e: PActive): TPathType;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := e.LocMin.PolyType;
end;
//------------------------------------------------------------------------------

function IsSamePolyType(const e1, e2: PActive): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := e1.LocMin.PolyType = e2.LocMin.PolyType;
end;
//------------------------------------------------------------------------------

function GetIntersectPoint(e1, e2: PActive): TPoint64;
var
  b1, b2, m: Double;
begin
  //if parallel then return the current pt of e1 ...
  if (e1.Dx = e2.Dx) then
  begin
    Result.Y := e1.Curr.Y;
    Result.X := TopX(e1, Result.Y);
    Exit;
  end
  else if e1.Dx = 0 then
  begin
    Result.X := e1.Bot.X;
    if IsHorizontal(e2) then
      Result.Y := e2.Bot.Y
    else
    begin
      with e2^ do b2 := Bot.Y - (Bot.X/Dx);
      Result.Y := round(Result.X/e2.Dx + b2);
    end;
  end
  else if e2.Dx = 0 then
  begin
    Result.X := e2.Bot.X;
    if IsHorizontal(e1) then
      Result.Y := e1.Bot.Y
    else
    begin
      with e1^ do b1 := Bot.Y - (Bot.X/Dx);
      Result.Y := round(Result.X/e1.Dx + b1);
    end;
  end else
  begin
    with e1^ do b1 := Bot.X - Bot.Y * Dx;
    with e2^ do b2 := Bot.X - Bot.Y * Dx;
    m := (b2-b1)/(e1.Dx - e2.Dx);
    Result.Y := round(m);
    if Abs(e1.Dx) < Abs(e2.Dx) then
      Result.X := round(e1.Dx * m + b1) else
      Result.X := round(e2.Dx * m + b2);
  end;
end;
//------------------------------------------------------------------------------

(*******************************************************************************
*  Dx:                             0(90deg)                                    *
*                                  |                                           *
*               +inf (180deg) <--- o ---> -inf (0deg)                          *
*******************************************************************************)
procedure SetDx(e: PActive);  {$IFDEF INLINING} inline; {$ENDIF}
var
  dy: Int64;
begin
  dy := (e.Top.Y - e.Bot.Y);
  if dy = 0 then e.dx := HORIZONTAL
  else e.Dx := (e.Top.X - e.Bot.X)/dy;
end;
//------------------------------------------------------------------------------

function NextVertex(e: PActive): PVertex; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if e.WindDx > 0 then
    Result := e.vertTop.next else
    Result := e.vertTop.prev;
end;
//------------------------------------------------------------------------------

function IsMaxima(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := vfLocMax in e.vertTop.flags;
end;
//------------------------------------------------------------------------------

procedure TerminateHotOpen(e: PActive);
begin
  if e.OutRec.startE = e then
    e.OutRec.startE := nil else
    e.OutRec.endE := nil;
  e.OutRec := nil;
end;
//------------------------------------------------------------------------------

function GetMaximaPair(e: PActive): PActive;
begin
  if IsHorizontal(e) then
  begin
    //we can't be sure whether the MaximaPair is on the left or right, so ...
    Result := e.PrevInAEL;
    while assigned(Result) and (Result.Curr.X >= e.Top.X) do
    begin
      if Result.vertTop = e.vertTop then Exit;  //Found!
      Result := Result.PrevInAEL;
    end;
    Result := e.NextInAEL;
    while assigned(Result) and (TopX(Result, e.Top.Y) <= e.Top.X) do
    begin
      if Result.vertTop = e.vertTop then Exit;  //Found!
      Result := Result.NextInAEL;
    end;
  end else
  begin
    Result := e.NextInAEL;
    while assigned(Result) do
    begin
      if Result.vertTop = e.vertTop then Exit;  //Found!
      Result := Result.NextInAEL;
    end;
  end;
  Result := nil;
end;
//------------------------------------------------------------------------------

function PointCount(pts: TOutPt): Integer; {$IFDEF INLINING} inline; {$ENDIF}
var
  p: TOutPt;
begin
  Result := 0;
  if not Assigned(pts) then Exit;
  p := pts;
  repeat
    Inc(Result);
    p := p.Next;
  until p = pts;
end;
//------------------------------------------------------------------------------

procedure DisposePolyPts(pp: TOutPt);  {$IFDEF INLINING} inline; {$ENDIF}
var
  tmpPp: TOutPt;
begin
  pp.Prev.Next := nil;
  while Assigned(pp) do
  begin
    tmpPp := pp;
    pp := pp.Next;
    tmpPp.Free;
  end;
end;
//------------------------------------------------------------------------------

function LocMinListSort(item1, item2: Pointer): Integer;
var
  dy: Int64;
begin
  dy := PLocalMinima(item2).vertex.Pt.Y - PLocalMinima(item1).vertex.Pt.Y;
  if dy < 0 then Result := -1
  else if dy > 0 then Result := 1
  else Result := 0;
end;
//------------------------------------------------------------------------------

procedure SetOrientation(outRec: TOutRec; e1, e2: PActive);
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  outRec.startE := e1;
  outRec.endE := e2;
  e1.OutRec := outRec;
  e2.OutRec := outRec;
end;
//------------------------------------------------------------------------------

procedure SwapOutRecs(e1, e2: PActive);
var
  or1, or2: TOutRec;
  e: PActive;
begin
  or1 := e1.OutRec;
  or2 := e2.OutRec;
  if (or1 = or2) then
  begin
    e := or1.startE;
    or1.startE := or1.endE;
    or1.endE := e;
    Exit;
  end;
  if assigned(or1) then
  begin
    if e1 = or1.startE then
      or1.startE := e2 else
      or1.endE := e2;
  end;
  if assigned(or2) then
  begin
    if e2 = or2.startE then
      or2.startE := e1 else
      or2.endE := e1;
  end;
  e1.OutRec := or2;
  e2.OutRec := or1;
end;
//------------------------------------------------------------------------------

function GetOwner(e: PActive): TOutRec;
begin
  if IsHorizontal(e) and (e.Top.X < e.Bot.X) then
  begin
    e := e.NextInAEL;
    while assigned(e) and (not IsHotEdge(e) or IsOpen(e)) do
      e := e.NextInAEL;
    if not assigned(e) then Result := nil
    else if (e.OutRec.Flag = orOuter) = (e.OutRec.startE = e) then
      Result := e.OutRec.Owner
    else Result := e.OutRec;
  end else
  begin
    e := e.PrevInAEL;
    while assigned(e) and (not IsHotEdge(e) or IsOpen(e)) do
      e := e.PrevInAEL;
    if not assigned(e) then Result := nil
    else if (e.OutRec.Flag = orOuter) = (e.OutRec.endE = e) then
      Result := e.OutRec.Owner
    else Result := e.OutRec;
  end;
end;
//------------------------------------------------------------------------------

function EdgesAdjacentInSel(node: PIntersectNode): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  with node^ do
    Result := (Edge1.NextInSEL = Edge2) or (Edge1.PrevInSEL = Edge2);
end;
//------------------------------------------------------------------------------

function IntersectListSort(node1, node2: Pointer): Integer;
begin
  result := PIntersectNode(node2).Pt.Y - PIntersectNode(node1).Pt.Y;
end;

//------------------------------------------------------------------------------
// TClipper methods ...
//------------------------------------------------------------------------------

constructor TClipper.Create;
begin
  FLocMinList := TList.Create;
  FOutRecList := TList.Create;
  FIntersectList := TList.Create;
  FVertexList := TList.Create;
  Clear;
end;
//------------------------------------------------------------------------------

destructor TClipper.Destroy;
begin
  Clear;
  FLocMinList.Free;
  FOutRecList.Free;
  FIntersectList.Free;
  FVertexList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TClipper.CleanUp;
begin
  try
    while assigned(FActives) do DeleteFromAEL(FActives);
    DisposeScanLineList;
    DisposeAllOutRecs;
  except
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.Clear;
begin
  DisposeVerticesAndLocalMinima;
  FCurrentLocMinIdx := 0;
  FLocMinListSorted := false;
  FHasOpenPaths := False;
end;
//------------------------------------------------------------------------------

procedure TClipper.Reset;
var
  i: Integer;
begin
  if not FLocMinListSorted then
  begin
    FLocMinList.Sort(LocMinListSort);
    FLocMinListSorted := true;
  end;
  for i := 0 to FLocMinList.Count -1 do
    InsertScanLine(PLocalMinima(FLocMinList[i]).vertex.Pt.Y);
  FCurrentLocMinIdx := 0;
  FActives := nil;
  FSel := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertScanLine(const Y: Int64);
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

function TClipper.PopScanLine(out Y: Int64): Boolean;
var
  sl: PScanLine;
begin
  Result := assigned(FScanLine);
  if not Result then Exit;
  Y := FScanLine.Y;
  sl := FScanLine;
  FScanLine := FScanLine.Next;
  dispose(sl);
end;
//------------------------------------------------------------------------------

function TClipper.PopLocalMinima(Y: Int64;
  out localMinima: PLocalMinima): Boolean;
begin
  Result := false;
  if FCurrentLocMinIdx = FLocMinList.Count then Exit;
  localMinima := PLocalMinima(FLocMinList[FCurrentLocMinIdx]);
  if (localMinima.vertex.Pt.Y = Y) then
  begin
    inc(FCurrentLocMinIdx);
    Result := true;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeScanLineList;
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

procedure TClipper.DisposeOutRec(index: Integer);
var
  outRec: TOutRec;
begin
  outRec := FOutRecList[index];
  if Assigned(outRec.Pts) then DisposePolyPts(outRec.Pts);
  outRec.Free;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeAllOutRecs;
var
  i: Integer;
begin
  for i := 0 to FOutRecList.Count -1 do DisposeOutRec(i);
  FOutRecList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeVerticesAndLocalMinima;
var
  i: Integer;
begin
  for i := 0 to FLocMinList.Count -1 do
    Dispose(PLocalMinima(FLocMinList[i]));
  FLocMinList.Clear;
  for i := 0 to FVertexList.Count -1 do FreeMem(FVertexList[i]);
  FVertexList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddPathToVertexList(const p: TPath;
  polyType: TPathType; isOpen: Boolean);
var
  i, j, pathLen: Integer;
  isFlat, goingUp, p0IsMinima, p0IsMaxima: Boolean;
  v: PVertex;
  va: PVertexArray;

  procedure AddLocMin(vert: PVertex);
  var
    lm: PLocalMinima;
  begin
    if vfLocMin in vert.flags then Exit; //ensures vertex is added only once
    Include(vert.flags, vfLocMin);
    new(lm);
    lm.vertex := vert;
    lm.PolyType := polyType;
    lm.IsOpen := isOpen;
    FLocMinList.Add(lm);                 //nb: sorted in Reset()
  end;
  //----------------------------------------------------------------------------

begin
  pathLen := length(p);
  while (pathLen > 1) and PointsEqual(p[pathLen -1], p[0]) do dec(pathLen);
  if (pathLen < 2) then Exit;

  p0IsMinima := false;
  p0IsMaxima := false;
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
      p0IsMinima := p[i].Y < p[0].Y; //p[0].Y == a minima
    end else
    begin
      i := pathLen -1;
      while p[i].Y = p[0].Y do dec(i);
      p0IsMaxima := p[i].Y > p[0].Y; //p[0].Y == a maxima
    end;
  end;

  GetMem(va, sizeof(TVertex) * pathLen);
  FVertexList.Add(va);
  va[0].Pt := p[0];
  va[0].flags := [];

  if isOpen then
  begin
    include(va[0].flags, vfOpenStart);
    if goingUp then
      AddLocMin(@va[0]) else
      include(va[0].flags, vfLocMax);
  end;

  //nb: polygon orientation is determined later (see InsertLocalMinimaIntoAEL).
  i := 0;
  for j := 1 to pathLen -1 do
  begin
    if PointsEqual(p[j], va[i].Pt) then Continue; //ie skips duplicates
    va[j].Pt := p[j];
    va[j].flags := [];
    va[i].next := @va[j];
    va[j].prev := @va[i];
    if (p[j].Y > p[i].Y) and goingUp then
    begin
      include(va[i].flags, vfLocMax);
      goingUp := false;
    end
    else if (p[j].Y < p[i].Y) and not goingUp then
    begin
      goingUp := true;
      AddLocMin(@va[i]);
    end;
    i := j;
  end;
  //i: index of the last vertex in the path.
  va[i].next := @va[0];
  va[0].prev := @va[i];

  if isOpen then
  begin
    include(va[i].flags, vfOpenEnd);
    if goingUp then
      include(va[i].flags, vfLocMax) else
      AddLocMin(@va[i]);
  end
  else if goingUp then
  begin
    //going up so find local maxima ...
    v := @va[i];
    while (v.Next.Pt.Y <= v.Pt.Y) do v := v.next;
    include(v.flags, vfLocMax);
    if p0IsMinima then AddLocMin(@va[0]); //ie just turned to going up
  end else
  begin
    //going down so find local minima ...
    v := @va[i];
    while (v.Next.Pt.Y >= v.Pt.Y) do v := v.next;
    AddLocMin(v);
    if p0IsMaxima then include(va[0].flags, vfLocMax);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddPath(const path: TPath; PolyType: TPathType;
  isOpen: Boolean);
begin
  if isOpen then
  begin
    if (PolyType = ptClip) then
      raise EClipperLibException.Create(rsOpenPathSubOnly);
    FHasOpenPaths := true;
  end;
  FLocMinListSorted := false;
  AddPathToVertexList(path, polyType, isOpen);
end;
//------------------------------------------------------------------------------

procedure TClipper.AddPaths(const paths: TPaths; polyType: TPathType;
  isOpen: Boolean);
var
  i: Integer;
begin
  for i := 0 to high(paths) do AddPath(paths[i], polyType, isOpen);
end;
//------------------------------------------------------------------------------

function TClipper.IsContributingClosed(e: PActive): Boolean;
begin
  Result := false;
  case FFillRule of
    frNonZero: if abs(e.WindCnt) <> 1 then Exit;
    frPositive: if (e.WindCnt <> 1) then Exit;
    frNegative: if (e.WindCnt <> -1) then Exit;
  end;

  case FClipType of
    ctIntersection:
      case FFillRule of
        frEvenOdd, frNonZero: Result := (e.WindCnt2 <> 0);
        frPositive: Result := (e.WindCnt2 > 0);
        frNegative: Result := (e.WindCnt2 < 0);
      end;
    ctUnion:
      case FFillRule of
        frEvenOdd, frNonZero: Result := (e.WindCnt2 = 0);
        frPositive: Result := (e.WindCnt2 <= 0);
        frNegative: Result := (e.WindCnt2 >= 0);
      end;
    ctDifference:
      if GetPolyType(e) = ptSubject then
        case FFillRule of
          frEvenOdd, frNonZero: Result := (e.WindCnt2 = 0);
          frPositive: Result := (e.WindCnt2 <= 0);
          frNegative: Result := (e.WindCnt2 >= 0);
        end
      else
        case FFillRule of
          frEvenOdd, frNonZero: Result := (e.WindCnt2 <> 0);
          frPositive: Result := (e.WindCnt2 > 0);
          frNegative: Result := (e.WindCnt2 < 0);
        end;
    ctXor:
        Result := true;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsContributingOpen(e: PActive): Boolean;
begin
    case FClipType of
      ctIntersection:
        Result := (e.WindCnt2 <> 0);
      ctXor:
        Result := (e.WindCnt <> 0) <> (e.WindCnt2 <> 0);
      ctDifference:
        Result := (e.WindCnt2 = 0);
      else //ctUnion:
        Result := (e.WindCnt = 0) and (e.WindCnt2 = 0);
    end;
end;
//------------------------------------------------------------------------------

procedure TClipper.SetWindingLeftEdgeClosed(e: PActive);
var
  e2: PActive;
begin
  //Wind counts generally refer to polygon regions not edges, so here an edge's
  //WindCnt indicates the higher of the two wind counts of the regions touching
  //the edge. (Note also that adjacent region wind counts only ever differ
  //by one, and open paths have no meaningful wind directions or counts.)

  e2 := e.PrevInAEL;
  //find the nearest closed path edge of the same PolyType in AEL (heading left)
  while Assigned(e2) and (not IsSamePolyType(e2, e) or IsOpen(e2)) do
    e2 := e2.PrevInAEL;

  //todo: check open path with negative Winding
  if not Assigned(e2) then
  begin
    e.WindCnt := e.WindDx;
    e2 := FActives;
  end
  else if (FFillRule = frEvenOdd) then
  begin
    e.WindCnt := e.WindDx;
    e.WindCnt2 := e2.WindCnt2;
    e2 := e2.NextInAEL;
  end else
  begin
    //NonZero, positive, or negative filling here ...
    //if e's WindCnt is in the SAME direction as its WindDx, then e is either
    //an outer left or a hole right boundary, so leftE must be inside 'e'.
    //(neither e.WindCnt nor e.WindDx should ever be 0)
    if (e2.WindCnt * e2.WindDx < 0) then
    begin
      //opposite directions so leftE is outside 'e' ...
      if (Abs(e2.WindCnt) > 1) then
      begin
        //outside prev poly but still inside another.
        if (e2.WindDx * e.WindDx < 0) then
          //reversing direction so use the same WC
          e.WindCnt := e2.WindCnt else
          //otherwise keep 'reducing' the WC by 1 (ie towards 0) ...
          e.WindCnt := e2.WindCnt + e.WindDx;
      end
      //now outside all polys of same polytype so set own WC ...
      else e.WindCnt := e.WindDx;
    end else
    begin
      //leftE must be inside 'e'
      if (e2.WindDx * e.WindDx < 0) then
        //reversing direction so use the same WC
        e.WindCnt := e2.WindCnt
      else
        //otherwise keep 'increasing' the WC by 1 (ie away from 0) ...
        e.WindCnt := e2.WindCnt + e.WindDx;
    end;
    e.WindCnt2 := e2.WindCnt2;
    e2 := e2.NextInAEL;
  end;

  //update WindCnt2 ...
  if FFillRule = frEvenOdd then
    while (e2 <> e) do
    begin
      if IsSamePolyType(e2, e) or IsOpen(e2) then //do nothing
      else if e.WindCnt2 = 0 then e.WindCnt2 := 1
      else e.WindCnt2 := 0;
      e2 := e2.NextInAEL;
    end
  else
    while (e2 <> e) do
    begin
      if not IsSamePolyType(e2, e) and not IsOpen(e2) then
        Inc(e.WindCnt2, e2.WindDx);
      e2 := e2.NextInAEL;
    end;
end;
//------------------------------------------------------------------------------

procedure TClipper.SetWindingLeftEdgeOpen(e: PActive);
var
  e2: PActive;
  cnt1, cnt2: Integer;
begin
  e2 := FActives;
  if FFillRule = frEvenOdd then
  begin
    cnt1 := 0;
    cnt2 := 0;
    while (e2 <> e) do
    begin
      if (GetPolyType(e2) = ptClip) then inc(cnt2)
      else if not IsOpen(e2) then inc(cnt1);
      e2 := e2.NextInAEL;
    end;
    if Odd(cnt1) then e.WindCnt := 1 else e.WindCnt := 0;
    if Odd(cnt2) then e.WindCnt2 := 1 else e.WindCnt2 := 0;
  end else
  begin
    //if FClipType in [ctUnion, ctDifference] then e.WindCnt := e.WindDx;
    while (e2 <> e) do
    begin
      if (GetPolyType(e2) = ptClip) then inc(e.WindCnt2, e2.WindDx)
      else if not IsOpen(e2) then inc(e.WindCnt, e2.WindDx);
      e2 := e2.NextInAEL;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertLocalMinimaIntoAEL(const botY: Int64);

  procedure InsertEdgeIntoAEL(e, e2: PActive);
  begin
    if not Assigned(FActives) then
    begin
      e.PrevInAEL := nil;
      e.NextInAEL := nil;
      FActives := e;
      Exit;
    end;
    if not Assigned(e2) then
    begin
      if E2InsertsBeforeE1(FActives, e, false) then
      begin
        e.PrevInAEL := nil;
        e.NextInAEL := FActives;
        FActives.PrevInAEL := e;
        FActives := e;
        Exit;
      end;
      e2 := FActives;
      while Assigned(e2.NextInAEL) and
        E2InsertsBeforeE1(e, e2.NextInAEL, false) do
          e2 := e2.NextInAEL;
    end
    else
      while Assigned(e2.NextInAEL) and
        E2InsertsBeforeE1(e, e2.NextInAEL, true) do
          e2 := e2.NextInAEL;
    e.NextInAEL := e2.NextInAEL;
    if Assigned(e2.NextInAEL) then e2.NextInAEL.PrevInAEL := e;
    e.PrevInAEL := e2;
    e2.NextInAEL := e;
  end;
  //----------------------------------------------------------------------

var
  e: PActive;
  leftB, rightB: PActive;
  locMin: PLocalMinima;
  contributing: Boolean;
begin
  //Add any local minima at BotY ...
  while PopLocalMinima(botY, locMin) do
  begin

    if (vfOpenStart in locMin.vertex.flags) then
    begin
      leftB := nil;
    end else
    begin
      new(leftB);
      FillChar(leftB^, sizeof(TActive), 0);
      leftB.LocMin := locMin;
      leftB.OutRec := nil;
      leftB.Bot := locMin.vertex.Pt;
      leftB.vertTop := locMin.vertex.prev; //ie descending
      leftB.Top := leftB.vertTop.Pt;
      leftB.Curr := leftB.Bot;
      leftB.WindCnt2 := 0;
      leftB.WindDx := -1;
      SetDx(leftB);
    end;

    if (vfOpenEnd in locMin.vertex.flags) then
    begin
      rightB := nil;
    end else
    begin
      new(rightB);
      FillChar(rightB^, sizeof(TActive), 0);
      rightB.LocMin := locMin;
      rightB.OutRec := nil;
      rightB.Bot := locMin.vertex.Pt;
      rightB.vertTop := locMin.vertex.next; //ie ascending
      rightB.Top := rightB.vertTop.Pt;
      rightB.Curr := rightB.Bot;
      rightB.WindCnt2 := 0;
      rightB.WindDx := 1;
      SetDx(rightB);
    end;

    //Currently LeftB is just the descending bound and RightB is the ascending.
    //Now if the LeftB isn't on the left of RightB then we need swap them.
    if assigned(leftB) and assigned(rightB) then
    begin
      if IsHorizontal(leftB) then
      begin
        if (leftB.Top.X > leftB.Bot.X) then SwapActives(leftB, rightB);
      end
      else if IsHorizontal(rightB) then
      begin
        if (rightB.Top.X < rightB.Bot.X) then SwapActives(leftB, rightB);
      end
      else if (leftB.Dx < rightB.Dx) then SwapActives(leftB, rightB);
    end
    else if not assigned(leftB) then
    begin
      leftB := rightB;
      rightB := nil;
    end;

    InsertEdgeIntoAEL(leftB, nil);      //insert left edge
    if IsOpen(leftB) then
    begin
      SetWindingLeftEdgeOpen(leftB);
      contributing := IsContributingOpen(leftB);
    end else
    begin
      SetWindingLeftEdgeClosed(leftB);
      contributing := IsContributingClosed(leftB);
    end;

    if assigned(rightB) then
    begin
      rightB.WindCnt := leftB.WindCnt;
      rightB.WindCnt2 := leftB.WindCnt2;
      InsertEdgeIntoAEL(rightB, leftB); //insert right edge
      if contributing then
        AddLocalMinPoly(leftB, rightB, leftB.Bot);

      if IsHorizontal(rightB) then
        PushHorz(rightB) else
        InsertScanLine(rightB.Top.Y);
    end
    else if contributing then
      StartOpenPath(leftB, leftB.Bot);

    if IsHorizontal(leftB) then
      PushHorz(leftB) else
      InsertScanLine(leftB.Top.Y);

    if assigned(rightB) and (leftB.NextInAEL <> rightB) then
    begin
      //intersect edges that are between left and right bounds ...
      e := rightB.NextInAEL;
      MoveEdgeToFollowLeftInAEL(rightB, leftB); //move rightB to right of leftB
      while (rightB.NextInAEL <> e) do
      begin
        //now move rightB back to its proper position while intersecting edges
        IntersectEdges(rightB, rightB.NextInAEL, rightB.Bot);
        SwapPositionsInAEL(rightB, rightB.NextInAEL);
      end;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.PushHorz(e: PActive);
begin
  if assigned(FSel) then
    e.NextInSEL := FSel else
    e.NextInSEL := nil;
  FSel := e;
end;
//------------------------------------------------------------------------------

function TClipper.PopHorz(out e: PActive): Boolean;
begin
  Result := assigned(FSel);
  if not Result then Exit;
  e := FSel;
  FSel := FSel.NextInSEL;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64);
var
  outRec: TOutRec;
  op: TOutPt;
  swapSideNeeded: boolean;
begin
  outRec := CreateOutRec;
  outRec.Idx := FOutRecList.Add(outRec);
  outRec.Owner := GetOwner(e1);
  outRec.Pts := nil;
  outRec.PolyPath := nil;

  if IsOpen(e1) then
  begin
    outRec.Owner := nil;
    outRec.Flag := orOpen;
  end
  else if not assigned(outRec.Owner) or (outRec.Owner.Flag = orInner) then
    outRec.Flag := orOuter
  else
    outRec.Flag := orInner;

  //now set orientation ...
  swapSideNeeded := false;    //todo: recheck this with open paths
  if IsHorizontal(e1) then
  begin
    if  (e1.Top.X > e1.Bot.X) then swapSideNeeded := true;
  end else if IsHorizontal(e2) then
  begin
    if (e2.Top.X < e2.Bot.X) then swapSideNeeded := true
  end else if (e1.Dx < e2.Dx) then swapSideNeeded := true;
  if (outRec.Flag = orInner) = swapSideNeeded then
    SetOrientation(outRec, e1, e2) else
    SetOrientation(outRec, e2, e1);

  op := CreateOutPt;
  outRec.Pts := op;
  op.Pt := pt;
  op.Prev := op;
  op.Next := op;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64);
begin
  if not IsHotEdge(e2) then
    raise EClipperLibException.Create(rsClippingErr);
  AddOutPt(e1, pt);
  if  (e1.OutRec = e2.OutRec) then
  begin
    e1.outRec.startE := nil;
    e1.outRec.endE := nil;
    e1.OutRec := nil;
    e2.OutRec := nil;
  end
  //and to preserve the winding orientation of Outrec ...
  else if e1.OutRec.Idx < e2.OutRec.Idx then
    JoinOutrecPaths(e1, e2) else
    JoinOutrecPaths(e2, e1);
end;
//------------------------------------------------------------------------------

procedure TClipper.JoinOutrecPaths(e1, e2: PActive);
var
  p1_start, p1_end, p2_start, p2_end: TOutPt;
begin
  if (IsStartSide(e1) = IsStartSide(e2)) then
  begin
    //one or other edge orientation is wrong...
    if IsOpen(e1) then SwapSides(e2.OutRec)
    else if not FixOrientation(e1) and not FixOrientation(e2) then
      raise EClipperLibException.Create(rsClippingErr);
    if e1.OutRec.Owner = e2.OutRec then
      e1.OutRec.Owner := e2.OutRec.Owner;
  end;

  //join e2 outrec path onto e1 outrec path and then delete e2 outrec path
  //pointers. (see joining_outpt.svg)
  p1_start :=  e1.OutRec.Pts;
  p2_start :=  e2.OutRec.Pts;
  p1_end := p1_start.Next;
  p2_end := p2_start.Next;

  if IsStartSide(e1) then
  begin
    p2_end.Prev := p1_start;
    p1_start.Next := p2_end;
    p2_start.Next := p1_end;
    p1_end.Prev := p2_start;
    e1.OutRec.Pts := p2_start;
    e1.OutRec.startE := e2.OutRec.startE;
    if assigned(e1.OutRec.startE) then //ie closed path
      e1.OutRec.startE.OutRec := e1.OutRec;
  end else
  begin
    p1_end.Prev := p2_start;
    p2_start.Next := p1_end;
    p1_start.Next := p2_end;
    p2_end.Prev := p1_start;
    e1.OutRec.endE := e2.OutRec.endE;
    if assigned(e1.OutRec.endE) then //ie closed path
      e1.OutRec.endE.OutRec := e1.OutRec;
  end;

  //after joining, the e2.OutRec contains no vertices ...
  e2.OutRec.startE := nil;
  e2.OutRec.endE := nil;
  e2.OutRec.Pts := nil;
  e2.OutRec.Owner := e1.OutRec; //this may be redundant

  //and e1 and e2 are maxima and are about to be dropped from the Actives list.
  e1.OutRec := nil;
  e2.OutRec := nil;
end;
//------------------------------------------------------------------------------

function TClipper.CreateOutPt: TOutPt;
begin
  Result := TOutPt.Create;
end;
//------------------------------------------------------------------------------

function TClipper.CreateOutRec: TOutRec;
begin
  Result := TOutRec.Create;
end;
//------------------------------------------------------------------------------

function TClipper.AddOutPt(e: PActive; const pt: TPoint64): TOutPt;
var
  opStart, opEnd: TOutPt;
  toStart: Boolean;
begin
  //Outrec.OutPts: a circular double-linked-list of POutPt.
  toStart := IsStartSide(e);
  opStart := e.OutRec.Pts;
  opEnd := opStart.Next;
  if toStart then
  begin
    if PointsEqual(pt, opStart.Pt) then
    begin
      result := opStart;
      Exit;
    end;
  end
  else if PointsEqual(pt, opEnd.Pt) then
  begin
    result := opEnd;
    Exit;
  end;
  Result := CreateOutPt;
  Result.Pt := pt;
  opEnd.Prev := Result;
  Result.Prev := opStart;
  Result.Next := opEnd;
  opStart.Next := Result;
  if toStart then e.OutRec.Pts := Result;
end;
//------------------------------------------------------------------------------

procedure TClipper.StartOpenPath(e: PActive; const pt: TPoint64);
var
  OutRec: TOutRec;
  op: TOutPt;
begin
  assert(e.OutRec = nil, 'oops');
  OutRec := CreateOutRec;
  OutRec.Idx := FOutRecList.Add(OutRec);
  OutRec.Owner := nil;
  OutRec.Flag := orOpen;
  outRec.Pts := nil;
  outRec.PolyPath := nil;
  OutRec.startE := nil;
  OutRec.endE := nil;
  e.OutRec := OutRec;

  op := CreateOutPt;
  outRec.Pts := op;
  op.Pt := pt;
  op.Prev := op;
  op.Next := op;
end;
//------------------------------------------------------------------------------

procedure TClipper.UpdateEdgeIntoAEL(var e: PActive);
begin
  e.Bot := e.Top;
  e.vertTop := NextVertex(e);
  e.Top := e.vertTop.Pt;
  e.Curr := e.Bot;
  SetDx(e);
  if not IsHorizontal(e) then InsertScanLine(e.Top.Y);
end;
//------------------------------------------------------------------------------

procedure TClipper.IntersectEdges(e1, e2: PActive; pt: TPoint64);
var
  e1WindCnt, e2WindCnt, e1WindCnt2, e2WindCnt2: Integer;
begin
  e1.Curr := pt;
  e2.Curr := pt;

  //if either edge is an OPEN path ...
  if FHasOpenPaths and (IsOpen(e1) or IsOpen(e2)) then
  begin
    if (IsOpen(e1) and IsOpen(e2) ) then Exit;
    //the following line just avoids duplicating a whole lot of code ...
    if IsOpen(e2) then SwapActives(e1, e2);
    case FClipType of
      ctIntersection, ctDifference:
        if IsSamePolyType(e1, e2) or (abs(e2.WindCnt) <> 1) then Exit;
      ctUnion:
        if IsHotEdge(e1) <> ((abs(e2.WindCnt) <> 1) or
          (IsHotEdge(e1) <> (e2.WindCnt2 <> 0))) then Exit; //just works!
      ctXor:
        if (abs(e2.WindCnt) <> 1) then Exit;
    end;
    //toggle contribution ...
    if IsHotEdge(e1) then
    begin
      AddOutPt(e1, pt);
      TerminateHotOpen(e1);
    end
    else StartOpenPath(e1, pt);
    Exit;
  end;

  //update winding counts...
  //assumes that e1 will be to the right of e2 ABOVE the intersection
  if IsSamePolyType(e1, e2) then
  begin
    if FFillRule = frEvenOdd then
    begin
      e1WindCnt := e1.WindCnt;
      e1.WindCnt := e2.WindCnt;
      e2.WindCnt := e1WindCnt;
    end else
    begin
      if e1.WindCnt + e2.WindDx = 0 then
        e1.WindCnt := -e1.WindCnt else
        Inc(e1.WindCnt, e2.WindDx);
      if e2.WindCnt - e1.WindDx = 0 then
        e2.WindCnt := -e2.WindCnt else
        Dec(e2.WindCnt, e1.WindDx);
    end;
  end else
  begin
    if FFillRule <> frEvenOdd then Inc(e1.WindCnt2, e2.WindDx)
    else if e1.WindCnt2 = 0 then e1.WindCnt2 := 1
    else e1.WindCnt2 := 0;

    if FFillRule <> frEvenOdd then Dec(e2.WindCnt2, e1.WindDx)
    else if e2.WindCnt2 = 0 then e2.WindCnt2 := 1
    else e2.WindCnt2 := 0;
  end;

  case FFillRule of
    frPositive:
      begin
        e1WindCnt := e1.WindCnt;
        e2WindCnt := e2.WindCnt;
      end;
    frNegative:
      begin
        e1WindCnt := -e1.WindCnt;
        e2WindCnt := -e2.WindCnt;
      end;
    else
      begin
        e1WindCnt := abs(e1.WindCnt);
        e2WindCnt := abs(e2.WindCnt);
      end;
  end;

  if IsHotEdge(e1) and IsHotEdge(e2) then
  begin
    if not (e1WindCnt in [0,1]) or not (e2WindCnt in [0,1]) or
      (not IsSamePolyType(e1, e2) and (fClipType <> ctXor)) then
    begin
      AddLocalMaxPoly(e1, e2, pt);
    end else if IsStartSide(e1) then
    begin
      AddLocalMaxPoly(e1, e2, pt);
      AddLocalMinPoly(e1, e2, pt);
    end else
    begin
      AddOutPt(e1, pt);
      AddOutPt(e2, pt);
      SwapOutRecs(e1, e2);
    end;
  end else if IsHotEdge(e1) then
  begin
    if (e2WindCnt = 0) or (e2WindCnt = 1) then
    begin
      AddOutPt(e1, pt);
      SwapOutRecs(e1, e2);
    end;
  end
  else if IsHotEdge(e2) then
  begin
    if (e1WindCnt = 0) or (e1WindCnt = 1) then
    begin
      AddOutPt(e2, pt);
      SwapOutRecs(e1, e2);
    end;
  end
  else if  ((e1WindCnt = 0) or (e1WindCnt = 1)) and
    ((e2WindCnt = 0) or (e2WindCnt = 1)) then
  begin
    //neither Edge is currently contributing ...
    case FFillRule of
      frPositive:
      begin
        e1WindCnt2 := e1.WindCnt2;
        e2WindCnt2 := e2.WindCnt2;
      end;
      frNegative:
      begin
        e1WindCnt2 := -e1.WindCnt2;
        e2WindCnt2 := -e2.WindCnt2;
      end
      else
      begin
        e1WindCnt2 := abs(e1.WindCnt2);
        e2WindCnt2 := abs(e2.WindCnt2);
      end;
    end;

    if not IsSamePolyType(e1, e2) then
    begin
      AddLocalMinPoly(e1, e2, pt);
    end
    else if (e1WindCnt = 1) and (e2WindCnt = 1) then
      case FClipType of
        ctIntersection:
          if (e1WindCnt2 > 0) and (e2WindCnt2 > 0) then
            AddLocalMinPoly(e1, e2, pt);
        ctUnion:
          if (e1WindCnt2 <= 0) and (e2WindCnt2 <= 0) then
            AddLocalMinPoly(e1, e2, pt);
        ctDifference:
          if ((GetPolyType(e1) = ptClip) and (e1WindCnt2 > 0) and
            (e2WindCnt2 > 0)) or ((GetPolyType(e1) = ptSubject) and
            (e1WindCnt2 <= 0) and (e2WindCnt2 <= 0)) then
              AddLocalMinPoly(e1, e2, pt);
        ctXor:
          AddLocalMinPoly(e1, e2, pt);
      end
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DeleteFromAEL(e: PActive);
var
  aelPrev, aelNext: PActive;
begin
  aelPrev := e.PrevInAEL;
  aelNext := e.NextInAEL;
  if not Assigned(aelPrev) and not Assigned(aelNext) and
    (e <> FActives) then Exit; //already deleted
  if Assigned(aelPrev) then aelPrev.NextInAEL := aelNext
  else FActives := aelNext;
  if Assigned(aelNext) then aelNext.PrevInAEL := aelPrev;
  Dispose(e);
end;
//------------------------------------------------------------------------------

procedure TClipper.CopyActivesToSEL;
var
  e: PActive;
begin
  FSel := FActives;
  e := FActives;
  while Assigned(e) do
  begin
    e.PrevInSEL := e.PrevInAEL;
    e.NextInSEL := e.NextInAEL;
    e := e.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.CopyActivesToSELAdjustCurrX(topY: Int64);
var
  e: PActive;
begin
  FSel := FActives;
  e := FActives;
  while Assigned(e) do
  begin
    e.PrevInSEL := e.PrevInAEL;
    e.NextInSEL := e.NextInAEL;
    e.Curr.X := TopX(e, topY);
      e := e.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.ExecuteInternal(clipType: TClipType; fillRule: TFillRule): Boolean;
var
  Y: Int64;
  e: PActive;
begin
  Result := clipType = ctNone;
  if Result then Exit;
  try
    FFillRule := fillRule;
    FClipType := clipType;
    Reset;
    if not PopScanLine(Y) then Exit;
    ////////////////////////////////////////////////////////
    while true do
    begin
      InsertLocalMinimaIntoAEL(Y);
      while PopHorz(e) do ProcessHorizontal(e);
      if not PopScanLine(Y) then Break; //Y now top of scanbeam
      ProcessIntersections(Y);
      DoTopOfScanbeam(Y);
    end;
    ////////////////////////////////////////////////////////
    Result := True;
  except;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType; out closedPaths: TPaths;
  fillRule: TFillRule): Boolean;
var
  dummy: TPaths;
begin
  closedPaths := nil;
  Result := ExecuteInternal(clipType, fillRule);
  if Result then BuildResult(closedPaths, dummy);
  CleanUp;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType; out closedPaths, openPaths: TPaths;
  fillRule: TFillRule = frEvenOdd): Boolean;
begin
  closedPaths := nil;
  openPaths := nil;
  Result := ExecuteInternal(clipType, fillRule);
  if Result then BuildResult(closedPaths, openPaths);
  CleanUp;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType; var polytree: TPolyTree;
  out openPaths: TPaths; fillRule: TFillRule): Boolean;
begin
  if not assigned(polytree) then
    raise EClipperLibException.Create(rsPolyTreeErr);
  polytree.Clear;
  openPaths := nil;
  Result := ExecuteInternal(clipType, fillRule);
  if Result then BuildResult2(polytree, openPaths);
  CleanUp;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessIntersections(const topY: Int64);
begin
  BuildIntersectList(topY);
  if (FIntersectList.Count = 0) then Exit;
  try
    FixupIntersectionOrder;
    ProcessIntersectList;
  finally
    DisposeIntersectNodes; //clean up only needed if there's been an error
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeIntersectNodes;
var
  i: Integer;
begin
  for i := 0 to FIntersectList.Count - 1 do
    Dispose(PIntersectNode(FIntersectList[i]));
  FIntersectList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertNewIntersectNode(e1, e2: PActive; topY: Int64);
var
  pt: TPoint64;
  node: PIntersectNode;
begin
  pt := GetIntersectPoint(e1, e2);
  //Rounding errors can occasionally place the calculated intersection
  //point either below or above the scanbeam, so check and correct ...
  if (pt.Y > e1.Curr.Y) then
  begin
    pt.Y := e1.Curr.Y;      //E.Curr.Y is still the bottom of scanbeam
    //use the more vertical of the 2 edges to derive pt.X ...
    if (abs(e1.Dx) < abs(e2.Dx)) then
      pt.X := TopX(e1, pt.Y) else
      pt.X := TopX(e2, pt.Y);
  end else
  if pt.Y < topY then
  begin
    pt.Y := topY;          //TopY = top of scanbeam
    if e1.Top.Y = topY then
      pt.X := e1.Top.X
    else if e2.Top.Y = topY then
      pt.X := e2.Top.X
    else if (abs(e1.Dx) < abs(e2.Dx)) then
      pt.X := e1.Curr.X
    else
      pt.X := e2.Curr.X;
  end;

  new(node);
  node.Edge1 := e1;
  node.Edge2 := e2;
  node.Pt := pt;
  FIntersectList.Add(node);
end;
//------------------------------------------------------------------------------

procedure TClipper.BuildIntersectList(const topY: Int64);
var
  i, lCnt, rCnt, mul: integer;
  first, second, base, prevBase, tmp: PActive;
begin
  if not Assigned(FActives) or not Assigned(FActives.NextInAEL) then Exit;

  CopyActivesToSELAdjustCurrX(topY);

  //Merge sort FActives into their new positions at the top of scanbeam, and
  //create an intersection node every time an edge crosses over another ...
  //see https://stackoverflow.com/a/46319131/359538

	mul := 1;
	while (true) do
  begin
    first := FSel;
    prevBase := nil;
		//sort successive larger 'mul' count of nodes ...
		while assigned(first) do
    begin
			if (mul = 1) then
      begin
        second := first.NextInSEL;
        if not assigned(second) then
        begin
          first.MergeJump := nil;
          break;
        end;
        first.MergeJump := second.NextInSEL;
      end else
      begin
			  second := first.MergeJump;
        if not assigned(second) then
        begin
          first.MergeJump := nil;
          break;
        end;
        first.MergeJump := second.MergeJump;
      end;

      //now sort first and second groups ...
      base := first;
			lCnt := mul; rCnt := mul;
			while (lCnt > 0) and (rCnt > 0) do
			begin
				if (first.Curr.X > second.Curr.X) then
        begin
          // create one or more Intersect nodes ///////////
          tmp := second.PrevInSEL;
          for i := 1 to lCnt do
          begin
            //create a new intersect node...
            InsertNewIntersectNode(tmp, second, topY);
            tmp := tmp.PrevInSEL;
          end;
          /////////////////////////////////////////////////
          if (first = base) then
          begin
            if assigned(prevBase) then prevBase.MergeJump := second;
            base := second;
            base.MergeJump := first.MergeJump;
            if (first.PrevInSEL = nil) then FSel := second;
          end;
          tmp := second.NextInSEL;
          //now move the out of place edge to it's new position in SEL ...
          Insert2Before1InSel(first, second);
          second := tmp;
          if not assigned(second) then
          begin
            first := nil;
            break;
          end;
          dec(rCnt);
        end else
        begin
          first := first.NextInSEL;
          dec(lCnt);
        end;
      end;
      first := base.MergeJump;
      prevBase := base;
    end;
    if FSel.MergeJump = nil then Break
    else mul := mul shl 1;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessIntersectList;
var
  i: Integer;
begin
  for i := 0 to FIntersectList.Count - 1 do
  begin
    with PIntersectNode(FIntersectList[i])^ do
    begin
      IntersectEdges(Edge1, Edge2, Pt);
      SwapPositionsInAEL(Edge1, Edge2);
    end;
    dispose(PIntersectNode(FIntersectList[i]));
  end;
  FIntersectList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.FixupIntersectionOrder;
var
  i, j, cnt: Integer;
  node: PIntersectNode;
begin
  cnt := FIntersectList.Count;
  if cnt < 2 then Exit;
  //It's important that edge intersections are processed from the bottom up,
  //but it's also crucial that intersections only occur between adjacent edges.
  //The first sort here (a quicksort), arranges intersections relative to their
  //vertical positions within the scanbeam ...
  FIntersectList.Sort(IntersectListSort);

  //Now we simulate processing these intersections, and as we do, we make sure
  //that the intersecting edges remain adjacent. If they aren't, this simulated
  //intersection is delayed until such time as these edges do become adjacent.
  CopyActivesToSEL;
  for i := 0 to cnt - 1 do
  begin
    if not EdgesAdjacentInSel(FIntersectList[i]) then
    begin
      j := i + 1;
      while (j < cnt) and not EdgesAdjacentInSel(FIntersectList[j]) do inc(j);
      //Swap IntersectNodes ...
      node := FIntersectList[i];
      FIntersectList[i] := FIntersectList[j];
      FIntersectList[j] := node;
    end;
    with PIntersectNode(FIntersectList[i])^ do
      SwapPositionsInSEL(Edge1, Edge2);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInAEL(e1, e2: PActive);
var
  prev, next: PActive;
begin
  if e1.NextInAEL = e2 then
  begin
    next := e2.NextInAEL;
    if Assigned(next) then next.PrevInAEL := e1;
    prev := e1.PrevInAEL;
    if Assigned(prev) then prev.NextInAEL := e2;
    e2.PrevInAEL := prev;
    e2.NextInAEL := e1;
    e1.PrevInAEL := e2;
    e1.NextInAEL := next;
    if not Assigned(e2.PrevInAEL) then FActives := e2;
  end
  else if e2.NextInAEL = e1 then
  begin
    next := e1.NextInAEL;
    if Assigned(next) then next.PrevInAEL := e2;
    prev := e2.PrevInAEL;
    if Assigned(prev) then prev.NextInAEL := e1;
    e1.PrevInAEL := prev;
    e1.NextInAEL := e2;
    e2.PrevInAEL := e1;
    e2.NextInAEL := next;
    if not Assigned(e1.PrevInAEL) then FActives := e1;
  end else
    raise EClipperLibException.Create(rsClippingErr);
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInSEL(e1, e2: PActive);
var
  prev, next: PActive;
begin
  if e1.NextInSEL = e2 then
  begin
    next := e2.NextInSEL;
    if Assigned(next) then next.PrevInSEL := e1;
    prev := e1.PrevInSEL;
    if Assigned(prev) then prev.NextInSEL := e2;
    e2.PrevInSEL := prev;
    e2.NextInSEL := e1;
    e1.PrevInSEL := e2;
    e1.NextInSEL := next;
    if not Assigned(e2.PrevInSEL) then FSel := e2;
  end
  else if e2.NextInSEL = e1 then
  begin
    next := e1.NextInSEL;
    if Assigned(next) then next.PrevInSEL := e2;
    prev := e2.PrevInSEL;
    if Assigned(prev) then prev.NextInSEL := e1;
    e1.PrevInSEL := prev;
    e1.NextInSEL := e2;
    e2.PrevInSEL := e1;
    e2.NextInSEL := next;
    if not Assigned(e1.PrevInSEL) then FSel := e1;
  end else
    raise EClipperLibException.Create(rsClippingErr);
end;
//------------------------------------------------------------------------------

procedure TClipper.Insert2Before1InSel(first, second: PActive);
var
  prev, next: PActive;
begin
  //remove second from list ...
  prev := second.PrevInSEL;
  next := second.NextInSEL;
  prev.NextInSEL := next; //always a prev since we're moving from right to left
  if Assigned(next) then next.PrevInSEL := prev;
  //insert back into list ...
  prev := first.PrevInSEL;
  if assigned(prev) then prev.NextInSEL := second;
  first.PrevInSEL := second;
  second.PrevInSEL := prev;
  second.NextInSEL := first;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontal(horzEdge: PActive);
var
  e, eNext, maxPair: PActive;
  horzLeft, horzRight: Int64;
  isLeftToRight: Boolean;
  pt: TPoint64;
  isMax: Boolean;

  procedure ResetHorzDirection;
  var
    e: PActive;
  begin
    if (horzEdge.Bot.X = horzEdge.Top.X) then
    begin
      //the horizontal edge is going nowhere ...
      horzLeft := horzEdge.Curr.X;
      horzRight := horzEdge.Curr.X;
      e := horzEdge.NextInAEL;
      while assigned(e) and (e <> maxPair) do
        e := e.NextInAEL;
      isLeftToRight := assigned(e);
    end
    else if horzEdge.Curr.X < horzEdge.Top.X then
    begin
      horzLeft := horzEdge.Curr.X;
      horzRight := horzEdge.Top.X;
      isLeftToRight := true;
    end else
    begin
      horzLeft := horzEdge.Top.X;
      horzRight := horzEdge.Curr.X;
      isLeftToRight := false;
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
  if not IsOpen(horzEdge) then
  begin
    pt := horzEdge.Bot;
    while not IsMaxima(horzEdge) and
      (NextVertex(horzEdge).Pt.Y = pt.Y) do
        UpdateEdgeIntoAEL(horzEdge);
    horzEdge.Bot := pt;
    horzEdge.Curr := pt;
  end;

  maxPair := nil;
  if IsMaxima(horzEdge) and (not IsOpen(horzEdge) or
      ([vfOpenStart, vfOpenEnd] * horzEdge.vertTop.flags = [])) then
        maxPair := GetMaximaPair(horzEdge);

  ResetHorzDirection;
  if IsHotEdge(horzEdge) then
    AddOutPt(horzEdge, horzEdge.Curr);

  while true do //loops through consec. horizontal edges (if open)
  begin
    isMax := IsMaxima(horzEdge);
    if isLeftToRight  then
      e := horzEdge.NextInAEL else
      e := horzEdge.PrevInAEL;

    while assigned(e) do
    begin
      //Break if we've gone past the end of the horizontal ...
      if (isLeftToRight and (e.Curr.X > horzRight)) or
        (not isLeftToRight and (e.Curr.X < horzLeft)) then Break;
      //or if we've got to the end of an intermediate horizontal edge ...
      if (E.Curr.X = horzEdge.Top.X) and not isMax and not IsHorizontal(e) then
      begin
        pt := NextVertex(horzEdge).Pt;
        if(isLeftToRight and (TopX(E, pt.Y) >= pt.X)) or
          (not isLeftToRight and (TopX(E, pt.Y) <= pt.X)) then Break;
      end;

      if (e = maxPair) then
      begin
        if IsHotEdge(horzEdge)  then
        begin
          if isLeftToRight then
            AddLocalMaxPoly(horzEdge, e, horzEdge.Top) else
            AddLocalMaxPoly(e, horzEdge, horzEdge.Top);
        end;
        DeleteFromAEL(e);
        DeleteFromAEL(horzEdge);
        Exit;
      end;

      if (isLeftToRight) then
      begin
        pt := Point64(e.Curr.X, horzEdge.Curr.Y);
        IntersectEdges(horzEdge, e, pt);
      end else
      begin
        pt := Point64(e.Curr.X, horzEdge.Curr.Y);
        IntersectEdges(e, horzEdge, pt);
      end;

      if isLeftToRight then
        eNext := e.NextInAEL else
        eNext := e.PrevInAEL;
      SwapPositionsInAEL(horzEdge, e);
      e := eNext;
    end;

    //check if we've finished with (consecutive) horizontals ...
    if isMax or (NextVertex(horzEdge).Pt.Y <> horzEdge.Top.Y) then Break;

    //still more horizontals in bound to process ...
    UpdateEdgeIntoAEL(horzEdge);
    ResetHorzDirection;

    if IsOpen(horzEdge) then
    begin
      if IsMaxima(horzEdge) then maxPair := GetMaximaPair(horzEdge);
      if IsHotEdge(horzEdge) then AddOutPt(horzEdge, horzEdge.Bot);
    end;
  end;

  if IsHotEdge(horzEdge) then
    AddOutPt(horzEdge, horzEdge.Top);

  if not IsOpen(horzEdge) then
    UpdateEdgeIntoAEL(horzEdge) //this is the end of an intermediate horiz.
  else if not IsMaxima(horzEdge) then
    UpdateEdgeIntoAEL(horzEdge)
  else if not assigned(maxPair) then //ie open at top
    DeleteFromAEL(horzEdge)
  else if IsHotEdge(horzEdge) then
      AddLocalMaxPoly(horzEdge, maxPair, horzEdge.Top)
  else
  begin
    DeleteFromAEL(maxPair); DeleteFromAEL(horzEdge);
  end;

end;
//------------------------------------------------------------------------------

procedure TClipper.DoTopOfScanbeam(Y: Int64);
var
  e: PActive;
begin
  FSel := nil;             //FSel reused to flag horizontals
  e := FActives;
  while Assigned(e) do
  begin
    //nb: E will never be horizontal at this point
    if (e.Top.Y = Y) then
    begin
      e.Curr := e.Top;     //needed for horizontal processing
      if IsMaxima(e) then
      begin
        e := DoMaxima(e);  //TOP OF BOUND (MAXIMA)
        Continue;
      end else
      begin
        //INTERMEDIATE VERTEX ...
        UpdateEdgeIntoAEL(e);
        if IsHotEdge(e) then AddOutPt(e, e.Bot);
        if IsHorizontal(e) then
          PushHorz(e);     //horizontals are processed later
      end;
    end
    else
    begin
      e.Curr.Y := Y;
      e.Curr.X := TopX(e, Y);
    end;
    e := e.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.DoMaxima(e: PActive): PActive;
var
  eNext, ePrev, eMaxPair: PActive;
begin
  ePrev := e.PrevInAEL;
  eNext := e.NextInAEL;
  Result := eNext;

  if IsOpen(e) and ([vfOpenStart, vfOpenEnd] * e.vertTop.flags <> []) then
  begin
    if IsHotEdge(e) then AddOutPt(e, e.Top);
    if not IsHorizontal(e) then
    begin
      if IsHotEdge(e) then TerminateHotOpen(e);
      DeleteFromAEL(e);
    end;
    Exit;
  end else
  begin
    eMaxPair := GetMaximaPair(e);
    if not assigned(eMaxPair) then Exit; //EMaxPair is a horizontal ...
  end;

  //only non-horizontal maxima here.
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

procedure TClipper.BuildResult(out closedPaths, openPaths: TPaths);
var
  i, j, cnt, cntClosed, cntOpen: Integer;
  outRec: TOutRec;
  op: TOutPt;
begin
  cntClosed := 0;
  cntOpen := 0;
  SetLength(closedPaths, FOutRecList.Count);
  SetLength(openPaths, FOutRecList.Count);
  for i := 0 to FOutRecList.Count -1 do
  begin
    outRec := FOutRecList[i];
    if not assigned(outRec.Pts) then Continue;

    //to preserve orientation, start at the back ...
    op := outRec.Pts.Next;
    cnt := PointCount(op);
    //avoid duplicate start and end points for polygons ...
    if (outRec.Flag = orOpen) and PointsEqual(op.Pt, op.Prev.Pt) then dec(cnt);

    if (outRec.Flag = orOpen) then
    begin
      if (Cnt < 2) then Continue;
      SetLength(openPaths[cntOpen], cnt);
      for j := 0 to cnt -1 do
      begin
        openPaths[cntOpen][j] := op.Pt;
        op := op.Next;
      end;
      Inc(cntOpen);
    end else
    begin
      if (Cnt < 3) then Continue;
      SetLength(closedPaths[cntClosed], cnt);
      for j := 0 to cnt -1 do
      begin
        closedPaths[cntClosed][j] := op.Pt;
        op := op.Next;
      end;
      Inc(cntClosed);
    end;
  end;
  SetLength(closedPaths, cntClosed);
  SetLength(openPaths, cntOpen);
end;
//------------------------------------------------------------------------------

procedure TClipper.BuildResult2(polyTree: TPolyTree; out openPaths: TPaths);
var
  i, j, cnt, cntOpen: Integer;
  outRec: TOutRec;
  op: TOutPt;
  path: TPath;
begin
  setLength(openPaths, FOutRecList.Count);
  cntOpen := 0;
  for i := 0 to FOutRecList.Count -1 do
    if Assigned(FOutRecList[i]) then
    begin
      outRec := FOutRecList[i];
      if not assigned(outRec.Pts) then Continue;

      op := outRec.Pts.Next;
      cnt := PointCount(op);
      //avoid duplicate start and end points ...
      if PointsEqual(op.Pt, outRec.Pts.Pt) then dec(cnt);

      if (cnt < 3) then
      begin
        if (outRec.Flag <> orOpen) or (cnt < 2) then Continue;
      end;

      SetLength(path, cnt);
      for j := 0 to cnt -1 do
      begin
        path[j] := op.Pt;
        op := op.Next;
      end;

      if (outRec.Flag = orOpen) then
      begin
        openPaths[cntOpen] := path;
        inc(cntOpen);
      end
      else if assigned(outRec.Owner) and assigned(outRec.Owner.PolyPath) then
        outRec.PolyPath := outRec.Owner.PolyPath.AddChild(path)
      else
        outRec.PolyPath := polyTree.AddChild(path);
    end;
  setLength(openPaths, cntOpen);
end;
//------------------------------------------------------------------------------

function TClipper.GetBounds: TRect64;
var
  i: Integer;
  v, vStart: PVertex;
begin
  if FVertexList.Count = 0 then
    Result := Rect64(0, 0, 0, 0)
  else
    with PVertex(FVertexList[0]).Pt do
      Result := Rect64(X, Y, X, Y);

  for i := 0 to FVertexList.Count -1 do
  begin
    vStart := FVertexList[i];
    v := vStart;
    repeat
      if v.Pt.X < Result.Left then Result.Left := v.Pt.X
      else if v.Pt.X > Result.Right then Result.Right := v.Pt.X;
      if v.Pt.Y < Result.Top then Result.Top := v.Pt.Y
      else if v.Pt.Y > Result.Bottom then Result.Bottom := v.Pt.Y;
      v := v.next;
    until v = vStart;
  end;
end;

//------------------------------------------------------------------------------
//  TPolyPath class
//------------------------------------------------------------------------------

constructor TPolyPath.Create;
begin
  FChildList := TList.Create;
end;
//------------------------------------------------------------------------------

destructor TPolyPath.Destroy;
begin
  Clear;
  FChildList.Free;
  inherited Destroy;
end;
//------------------------------------------------------------------------------

procedure TPolyPath.Clear;
var
  i: Integer;
begin
  for i := 0 to FChildList.Count -1 do
    TPolyPath(FChildList[i]).Free;
  FChildList.Clear;
end;
//------------------------------------------------------------------------------

function  TPolyPath.GetChild(index: Integer): TPolyPath;
begin
  if (index < 0) or (index >= FChildList.Count) then
    Result := nil else
    Result := TPolyPath(FChildList[index]);
end;
//------------------------------------------------------------------------------

function  TPolyPath.IsHoleNode: Boolean;
begin
  Result := not assigned(FParent) or not FParent.IsHoleNode;
end;
//------------------------------------------------------------------------------

function  TPolyPath.GetChildCnt: Integer;
begin
  Result := FChildList.Count;
end;
//------------------------------------------------------------------------------

function TPolyPath.AddChild(const path: TPath): TPolyPath;
begin
  Result := TPolyPath.Create;
  Result.FPath := path;
  FChildList.Add(Result);
  Result.FParent := self;
end;
//------------------------------------------------------------------------------

end.

