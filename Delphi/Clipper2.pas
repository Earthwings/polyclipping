unit Clipper2;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  10 September 2017                                               *
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
  TPoint64 = record X, Y: Int64; end;

  TPath = array of TPoint64;
  TPaths = array of TPath;

  TRect64 = record Left, Top, Right, Bottom: Int64; end;

  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);
  //By far the most widely used winding rules for polygon filling are EvenOdd
  //and NonZero (see GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32).
  //https://www.w3.org/TR/SVG/painting.html
  TFillType = (ftEvenOdd, ftNonZero, ftPositive, ftNegative);

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
    PolyType  : TPolyType;
    IsOpen    : Boolean;
  end;

  POutRec = ^TOutRec;

  PActive = ^TActive;
  TActive = record
    Bot      : TPoint64;
    Curr     : TPoint64;
    Top      : TPoint64;
    Dx       : double;        //inverse of edge slope (zero = vertical)
    WindDx   : integer;       //wind direction (ascending: +1; descending: -1)
    WindCnt  : integer;       //edge wind count of
    WindCnt2 : integer;       //wind count of opposite TPolyType
    OutRec   : POutRec;
    //AEL - active edge list (Vatti's AET - active edge table)
    PrevInAEL: PActive;
    NextInAEL: PActive;
    //SEL - 'sorted' edge list (Vatti's ST - sorted table)
    //    -  also (re)used in processing horizontals.
    PrevInSEL: PActive;
    NextInSEL: PActive;
    vertTop  : PVertex;
    LocMin   : PLocalMinima; //bottom of bound
  end;

  PScanLine = ^TScanLine;
  TScanLine = record
    Y        : Int64;
    Next     : PScanLine;
  end;

  POutPt = ^TOutPt;
  TOutPt = record
    Pt       : TPoint64;
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
    Idx      : integer;
    Owner    : POutRec;
    Pts      : POutPt;
    StartE   : PActive;
    EndE     : PActive;
    Flags    : TOutRecFlags;
    PolyPath : TPolyPath;
  end;

  TClipper2 = class
  private
    FScanLine           : PScanLine;
    FLocMinListSorted   : Boolean;
    FHasOpenPaths       : Boolean;
    FCurrentLocMinIdx   : integer;
    FIntersectList      : TList;
    FClipType           : TClipType;
    FFillType           : TFillType;
    FExecuteLocked      : Boolean;
    FOutRecList         : TList;
    FLocMinList         : TList;
    FVertexList         : TList;
    FActives            : PActive; //see AEL above
    FSel                : PActive; //see SEL above

    procedure Reset; virtual;
    procedure AddPathToVertexList(const p: TPath;
      polyType: TPolyType; isOpen: Boolean);
    procedure InsertScanLine(const Y: Int64);
    function PopScanLine(out Y: Int64): Boolean;
    function PopLocalMinima(Y: Int64;
      out localMinima: PLocalMinima): Boolean;
    procedure DisposeScanLineList;
    procedure DisposeLocalMinimaList;
    procedure DisposePolyPts(pp: POutPt);
    procedure DisposeOutRec(index: integer);
    procedure DisposeAllOutRecs;
    function IsContributing(e: PActive): Boolean;
    procedure SetWindingCount(edge: PActive);
    procedure InsertLocalMinimaIntoAEL(const botY: Int64);
    procedure DeleteFromAEL(e: PActive);
    procedure AddOutPt(e: PActive; const pt: TPoint64);
    procedure StartOpenPath(e: PActive; const pt: TPoint64);
    function GetOwner(e: PActive): POutRec;
    procedure AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64);
    procedure AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64);
    procedure CopyActivesToSEL;
    procedure UpdateEdgeIntoAEL(var e: PActive);
    procedure SwapOutRecs(e1, e2: PActive);
    procedure IntersectEdges(e1, e2: PActive; pt: TPoint64);
    procedure ProcessIntersections(const topY: Int64);
    procedure DisposeIntersectNodes;
    procedure BuildIntersectList(const topY: Int64);
    procedure ProcessIntersectList;
    procedure FixupIntersectionOrder;
    procedure SwapPositionsInAEL(e1, e2: PActive);
    procedure SwapPositionsInSEL(e1, e2: PActive);
    procedure ProcessHorizontal(horzEdge: PActive);
    procedure DoTopOfScanbeam(Y: Int64);
    function DoMaxima(e: PActive): PActive;
    procedure JoinOutrecPaths(e1, e2: PActive);
    procedure BuildResult(out closedPaths, openPaths: TPaths);
    procedure BuildResult2(polyTree: TPolyTree; out openPaths: TPaths);
    procedure PushHorz(e: PActive); {$IFDEF INLINING} inline; {$ENDIF}
    function PopHorz(out e: PActive): Boolean;
    function ExecuteInternal(clipType: TClipType; fillType: TFillType): Boolean;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure CleanUp;
    procedure Clear; virtual;
    function GetBounds: TRect64;
    procedure AddPath(const path: TPath; polyType: TPolyType = ptSubject;
      isOpen: Boolean = false); virtual;
    procedure AddPaths(const paths: TPaths; polyType: TPolyType = ptSubject;
      isOpen: Boolean = false); virtual;

    function Execute(clipType: TClipType; out closedPaths: TPaths;
      fillType: TFillType = ftEvenOdd): Boolean; overload;

    function Execute(clipType: TClipType; out closedPaths, openPaths: TPaths;
      fillType: TFillType = ftEvenOdd): Boolean; overload;

    function Execute(clipType: TClipType; var polytree: TPolyTree;
      out openPaths: TPaths; fillType: TFillType = ftEvenOdd): Boolean; overload;
  end;

  TPolyPath = class
  private
    FParent    : TPolyPath;
    FPath      : TPath;
    FChildList : TList;
    function     GetChildCnt: integer;
    function     GetChild(index: integer): TPolyPath;
    function     IsHoleNode: boolean;
  public
    constructor  Create;  virtual;
    destructor   Destroy; override;
    procedure    Clear;
    function     AddChild(const path: TPath): TPolyPath;
    property     Parent: TPolyPath read FParent;
    property     IsHole: Boolean read IsHoleNode;
    property     Path: TPath read FPath;
    property     ChildCount: integer read GetChildCnt;
    property     Child[index: integer]: TPolyPath read GetChild;
  end;

  TPolyTree = class(TPolyPath);

  EClipperLibException = class(Exception);

function PointsEqual(const p1, p2: TPoint64): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
function Point64(const X, Y: Int64): TPoint64; overload;
function Point64(const X, Y: Double): TPoint64; overload;

const
  EmptyRect: TRect64 = (Left: 0; Top: 0; Right: 0; Bottom: 0);

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
  result := assigned(e.OutRec);
end;
//------------------------------------------------------------------------------

function IsStartSide(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := (e = e.OutRec.StartE);
end;
//------------------------------------------------------------------------------

function TopX(e: PActive; const currentY: Int64): Int64; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if currentY = e.Top.Y then Result := e.Top.X
  else if e.Top.X = e.Bot.X then Result := e.Bot.X
  else Result := e.Bot.X + Round(e.Dx*(currentY - e.Bot.Y));
end;
//------------------------------------------------------------------------------

function IsHorizontal(e: PActive): boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := e.Dx = HORIZONTAL;
end;
//------------------------------------------------------------------------------

function IsOpen(e: PActive): boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := e.LocMin.IsOpen;
end;
//------------------------------------------------------------------------------

function PointsEqual(const p1, p2: TPoint64): Boolean;
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

function GetTopDeltaX(e1, e2: PActive): Int64; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if e1.Top.Y > e2.Top.Y then
    result := TopX(e2, e1.Top.Y) - e1.Top.X else
    result := e2.Top.X - TopX(e1, e2.Top.Y);
  end;
//------------------------------------------------------------------------------

function E2InsertsBeforeE1(e1, e2: PActive; preferLeft: Boolean): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if e2.Curr.X = e1.Curr.X then
  begin
    if preferLeft then
      Result := GetTopDeltaX(e1, e2) <= 0 else
      Result := GetTopDeltaX(e1, e2) < 0;
  end else
    Result := e2.Curr.X < e1.Curr.X;
end;
//----------------------------------------------------------------------

function IsSamePolyType(const e1, e2: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := e1.LocMin.PolyType = e2.LocMin.PolyType;
end;
//------------------------------------------------------------------------------

function GetIntersectPoint(e1, e2: PActive): TPoint64;
var
  b1, b2, m: Double;
begin
  //if parallel then return the current pt of e1 ...
  if (e1.Dx = e2.Dx) then
  begin
    result.Y := e1.Curr.Y;
    result.X := TopX(e1, result.Y);
    Exit;
  end
  else if e1.Dx = 0 then
  begin
    result.X := e1.Bot.X;
    if IsHorizontal(e2) then
      result.Y := e2.Bot.Y
    else
    begin
      with e2^ do b2 := Bot.Y - (Bot.X/Dx);
      result.Y := round(result.X/e2.Dx + b2);
    end;
  end
  else if e2.Dx = 0 then
  begin
    result.X := e2.Bot.X;
    if IsHorizontal(e1) then
      result.Y := e1.Bot.Y
    else
    begin
      with e1^ do b1 := Bot.Y - (Bot.X/Dx);
      result.Y := round(result.X/e1.Dx + b1);
    end;
  end else
  begin
    with e1^ do b1 := Bot.X - Bot.Y * Dx;
    with e2^ do b2 := Bot.X - Bot.Y * Dx;
    m := (b2-b1)/(e1.Dx - e2.Dx);
    result.Y := round(m);
    if Abs(e1.Dx) < Abs(e2.Dx) then
      result.X := round(e1.Dx * m + b1) else
      result.X := round(e2.Dx * m + b2);
  end;
end;
//------------------------------------------------------------------------------

(*******************************************************************************
*  Dx:                             0(90deg)                                    *
*                                  |                                           *
*               +inf (180deg) <--- o ---> -inf (0deg)                          *
*******************************************************************************)
procedure SetDx(e: PActive);
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
    result := e.vertTop.next else
    result := e.vertTop.prev;
end;
//------------------------------------------------------------------------------

function IsMaxima(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := vfLocMax in e.vertTop.flags;
end;
//------------------------------------------------------------------------------

function GetMaximaPair(e: PActive): PActive;
begin
  if IsHorizontal(e) then
  begin
    //we can't be sure whether the MaximaPair is on the left or right, so ...
    result := e.PrevInAEL;
    while assigned(Result) and (Result.Curr.X >= e.Top.X) do
    begin
      if Result.vertTop = e.vertTop then Exit;  //Found!
      result := result.PrevInAEL;
    end;
    result := e.NextInAEL;
    while assigned(Result) and (TopX(Result, e.Top.Y) <= e.Top.X) do
    begin
      if Result.vertTop = e.vertTop then Exit;  //Found!
      result := result.NextInAEL;
    end;
  end else
  begin
    result := e.NextInAEL;
    while assigned(Result) do
    begin
      if Result.vertTop = e.vertTop then Exit;  //Found!
      result := result.NextInAEL;
    end;
  end;
  result := nil;
end;

//------------------------------------------------------------------------------
// TClipper2 methods ...
//------------------------------------------------------------------------------

constructor TClipper2.Create;
begin
  FLocMinList := TList.Create;
  FOutRecList := TList.Create;
  FIntersectList := TList.Create;
  FVertexList := TList.Create;
  Clear;
end;
//------------------------------------------------------------------------------

destructor TClipper2.Destroy;
begin
  Clear;
  FLocMinList.Free;
  FOutRecList.Free;
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
  FHasOpenPaths := False;
end;
//------------------------------------------------------------------------------

function LocMinListSort(item1, item2: Pointer): integer;
var
  dy: Int64;
begin
  dy := PLocalMinima(item2).vertex.Pt.Y - PLocalMinima(item1).vertex.Pt.Y;
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

procedure TClipper2.InsertScanLine(const Y: Int64);
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

function TClipper2.PopScanLine(out Y: Int64): Boolean;
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

function TClipper2.PopLocalMinima(Y: Int64;
  out localMinima: PLocalMinima): Boolean;
begin
  Result := false;
  if FCurrentLocMinIdx = FLocMinList.Count then exit;
  localMinima := PLocalMinima(FLocMinList[FCurrentLocMinIdx]);
  if (localMinima.vertex.Pt.Y = Y) then
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

procedure TClipper2.DisposePolyPts(pp: POutPt);
var
  tmpPp: POutPt;
begin
  pp.Prev.Next := nil;
  while Assigned(pp) do
  begin
    tmpPp := pp;
    pp := pp.Next;
    dispose(tmpPp);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeOutRec(index: integer);
var
  outRec: POutRec;
begin
  outRec := FOutRecList[index];
  if Assigned(outRec.Pts) then DisposePolyPts(outRec.Pts);
  Dispose(outRec);
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeAllOutRecs;
var
  i: integer;
begin
  for i := 0 to FOutRecList.Count -1 do DisposeOutRec(i);
  FOutRecList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DisposeLocalMinimaList;
var
  i: integer;
begin
  for i := 0 to FLocMinList.Count -1 do
    Dispose(PLocalMinima(FLocMinList[i]));
  FLocMinList.Clear;
  for i := 0 to FVertexList.Count -1 do FreeMem(FVertexList[i]);
  FVertexList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddPathToVertexList(const p: TPath;
  polyType: TPolyType; isOpen: Boolean);
var
  i, j, pathLen: integer;
  isFlat, goingUp, p0IsMinima, p0IsMaxima: boolean;
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
    if PointsEqual(p[j], va[i].Pt) then continue; //ie skips duplicates
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
  end else
  begin
    if goingUp then
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
  FVertexList.Add(va);
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddPath(const path: TPath; PolyType: TPolyType;
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

procedure TClipper2.AddPaths(const paths: TPaths; polyType: TPolyType;
  isOpen: Boolean);
var
  i: integer;
begin
  for i := 0 to high(paths) do AddPath(paths[i], polyType, isOpen);
end;
//------------------------------------------------------------------------------

function TClipper2.IsContributing(e: PActive): Boolean;
var
  ft: TFillType;
begin
  Result := false;
  ft := FFillType;
  case ft of
    ftEvenOdd: if IsOpen(e) and (e.WindCnt <> 1) then Exit;
    ftNonZero: if abs(e.WindCnt) <> 1 then Exit;
    ftPositive: if (e.WindCnt <> 1) then Exit;
    else if (e.WindCnt <> -1) then Exit;
  end;

  case FClipType of
    ctIntersection:
      case ft of
        ftEvenOdd, ftNonZero: Result := (e.WindCnt2 <> 0);
        ftPositive: Result := (e.WindCnt2 > 0);
        ftNegative: Result := (e.WindCnt2 < 0);
      end;
    ctUnion:
      case ft of
        ftEvenOdd, ftNonZero: Result := (e.WindCnt2 = 0);
        ftPositive: Result := (e.WindCnt2 <= 0);
        ftNegative: Result := (e.WindCnt2 >= 0);
      end;
    ctDifference:
      if e.LocMin.PolyType = ptSubject then
        case ft of
          ftEvenOdd, ftNonZero: Result := (e.WindCnt2 = 0);
          ftPositive: Result := (e.WindCnt2 <= 0);
          ftNegative: Result := (e.WindCnt2 >= 0);
        end
      else
        case ft of
          ftEvenOdd, ftNonZero: Result := (e.WindCnt2 <> 0);
          ftPositive: Result := (e.WindCnt2 > 0);
          ftNegative: Result := (e.WindCnt2 < 0);
        end;
      ctXor:
        if IsOpen(e) then
          case ft of
            ftEvenOdd, ftNonZero: Result := (e.WindCnt2 = 0);
            ftPositive: Result := (e.WindCnt2 <= 0);
            ftNegative: Result := (e.WindCnt2 >= 0);
          end
        else
          Result := true; //XOr is always contributing unless it's open.
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.SetWindingCount(edge: PActive);
var
  e, e2: PActive;
  inside: Boolean;
  ft: TFillType;
begin
  e := edge.PrevInAEL;
  //find the Edge of the same PolyType that immediately preceeds 'Edge' in AEL
  while Assigned(e) and (not IsSamePolyType(e, edge) or IsOpen(e)) do
    e := e.PrevInAEL;
  if not Assigned(e) then
  begin
    if IsOpen(edge) then
    begin
      ft := FFillType;
      if ft = ftNegative then
        edge.WindCnt := -1 else
        edge.WindCnt := 1;
    end
    else
      edge.WindCnt := edge.WindDx;
    e := FActives; //ie get ready to calc WindCnt2
  end
  else if IsOpen(edge) and (FClipType <> ctUnion) then
  begin
    edge.WindCnt := 1;
    edge.WindCnt2 := e.WindCnt2;
    e := e.NextInAEL; //ie get ready to calc WindCnt2
  end
  else if FFillType = ftEvenOdd then
  begin
    //even-odd filling ...
    if IsOpen(edge) then  //if edge is part of a line
    begin
      //are we inside a subj polygon ...
      inside := true;
      e2 := e.PrevInAEL;
      while assigned(e2) do
      begin
        if IsSamePolyType(e2, e) and not IsOpen(e2) then
          inside := not inside;
        e2 := e2.PrevInAEL;
      end;
      if inside then edge.WindCnt := 0
      else edge.WindCnt := 1;
    end
    else //else a polygon
    begin
      edge.WindCnt := edge.WindDx;
    end;
    edge.WindCnt2 := e.WindCnt2;
    e := e.NextInAEL; //ie get ready to calc WindCnt2
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    if (e.WindCnt * e.WindDx < 0) then
    begin
      //prev edge is 'decreasing' WindCount (WC) toward zero
      //so we're outside the previous polygon ...
      if (Abs(e.WindCnt) > 1) then
      begin
        //outside prev poly but still inside another.
        //when reversing direction of prev poly use the same WC
        if (e.WindDx * edge.WindDx < 0) then
          edge.WindCnt := e.WindCnt
        //otherwise continue to 'decrease' WC ...
        else edge.WindCnt := e.WindCnt + edge.WindDx;
      end
      else
        //now outside all polys of same polytype so set own WC ...
        if IsOpen(edge) then edge.WindCnt := 1
        else edge.WindCnt := edge.WindDx;
    end else
    begin
      //prev edge is 'increasing' WindCount (WC) away from zero
      //so we're inside the previous polygon ...
      if IsOpen(edge) then
      begin
        if (e.WindCnt < 0) then edge.WindCnt := e.WindCnt -1
        else edge.WindCnt := e.WindCnt +1;
      end
      //if wind direction is reversing prev then use same WC
      else if (e.WindDx * edge.WindDx < 0) then
        edge.WindCnt := e.WindCnt
      //otherwise add to WC ...
      else edge.WindCnt := e.WindCnt + edge.WindDx;
    end;
    edge.WindCnt2 := e.WindCnt2;
    e := e.NextInAEL; //ie get ready to calc WindCnt2
  end;

  //update WindCnt2 ...
  if FFillType = ftEvenOdd then
  begin
    //even-odd filling ...
    while (e <> edge) do
    begin
      if IsSamePolyType(e, edge) or IsOpen(e) then //do nothing
      else if edge.WindCnt2 = 0 then edge.WindCnt2 := 1
      else edge.WindCnt2 := 0;
      e := e.NextInAEL;
    end;
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    while (e <> edge) do
    begin
      if not IsSamePolyType(e, edge) and not IsOpen(e) then
        Inc(edge.WindCnt2, e.WindDx);
      e := e.NextInAEL;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.InsertLocalMinimaIntoAEL(const botY: Int64);

  procedure InsertEdgeIntoAEL(e, startE: PActive; preferLeft: Boolean);
  begin
    if not Assigned(FActives) then
    begin
      e.PrevInAEL := nil;
      e.NextInAEL := nil;
      FActives := e;
    end
    else if not Assigned(startE) and
      E2InsertsBeforeE1(FActives, e, preferLeft) then
    begin
      e.PrevInAEL := nil;
      e.NextInAEL := FActives;
      FActives.PrevInAEL := e;
      FActives := e;
    end else
    begin
      if not Assigned(startE) then startE := FActives;
      while Assigned(startE.NextInAEL) and
        not E2InsertsBeforeE1(startE.NextInAEL, e, preferLeft) do
        begin
          startE := startE.NextInAEL;
          preferLeft := false; //if there's one intervening then allow all
        end;
      e.NextInAEL := startE.NextInAEL;
      if Assigned(startE.NextInAEL) then
        startE.NextInAEL.PrevInAEL := e;
      e.PrevInAEL := startE;
      startE.NextInAEL := e;
    end;
  end;
  //----------------------------------------------------------------------

var
  e: PActive;
  leftB, rightB, tmp: PActive;
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
      if (IsHorizontal(leftB) and (leftB.Top.X > leftB.Bot.X)) or
       (not IsHorizontal(leftB) and (leftB.Dx < rightB.Dx)) then
       begin
          tmp := leftB;
          leftB := rightB;
          rightB := tmp;
       end;
    end
    else if not assigned(leftB) then
    begin
      leftB := rightB;
      rightB := nil;
    end;

    InsertEdgeIntoAEL(leftB, nil, false);      //insert left edge
    SetWindingCount(leftB);
    contributing := IsContributing(leftB);

    if assigned(rightB) then
    begin
      rightB.WindCnt := leftB.WindCnt;
      rightB.WindCnt2 := leftB.WindCnt2;
      InsertEdgeIntoAEL(rightB, leftB, false); //insert right edge
      if contributing then
        AddLocalMinPoly(leftB, rightB, leftB.Bot);

      if IsHorizontal(rightB) then
        PushHorz(rightB) else
        InsertScanLine(rightB.Top.Y);
    end
    else if IsContributing(leftB) then
    begin
      //ie open path that's not at a local minima
      StartOpenPath(leftB, leftB.Bot);
    end;

    if IsHorizontal(leftB) then
      PushHorz(leftB) else
      InsertScanLine(leftB.Top.Y);

    if assigned(rightB) and (leftB.NextInAEL <> rightB) then
    begin
      //intersect edges that are between left and right bounds ...
      e := leftB.NextInAEL;
      while (e <> rightB) do
      begin
        //nb: For calculating winding counts etc, IntersectEdges() assumes
        //that param1 will be to the right of param2 ABOVE the intersection ...
        IntersectEdges(rightB, e, rightB.Bot);
        e := e.NextInAEL;
      end;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure SetOutrecClockwise(outRec: POutRec; e1, e2: PActive);
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  outRec.StartE := e1;
  outRec.EndE := e2;
  e1.OutRec := outRec;
  e2.OutRec := outRec;
end;
//------------------------------------------------------------------------------

procedure SetOutrecCounterClockwise(outRec: POutRec; e1, e2: PActive);
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  outRec.StartE := e2;
  outRec.EndE := e1;
  e1.OutRec := outRec;
  e2.OutRec := outRec;
end;
//------------------------------------------------------------------------------

function TClipper2.GetOwner(e: PActive): POutRec;
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

procedure TClipper2.AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64);
var
  outRec: POutRec;
  op    : POutPt;
begin
  new(outRec);
  outRec.Idx := FOutRecList.Add(outRec);
  outRec.Owner := GetOwner(e1);
  if assigned(outRec.Owner) and (orOuter in outRec.Owner.Flags) then
    outRec.Flags := [] else
    outRec.Flags := [orOuter];
  if IsOpen(e1) then Include(outRec.Flags, orOpen);
  outRec.PolyPath := nil;

  //now set orientation ...
  if IsHorizontal(e1) then
  begin
    if IsHorizontal(e2) then
    begin
      if (orOuter in outRec.Flags) = (e1.Bot.X > e2.Bot.X) then
        SetOutrecClockwise(outRec, e1,e2) else
        SetOutrecCounterClockwise(outRec, e1,e2);
    end
    else if (orOuter in outRec.Flags) = (e1.Top.X < e1.Bot.X) then
      SetOutrecClockwise(outRec, e1,e2) else
      SetOutrecCounterClockwise(outRec, e1,e2);
  end
  else if IsHorizontal(e2) then
  begin
    if (orOuter in outRec.Flags) = (e2.Top.X > e2.Bot.X) then
      SetOutrecClockwise(outRec, e1,e2) else
      SetOutrecCounterClockwise(outRec, e1,e2);
  end
  else if (orOuter in outRec.Flags) = (e1.Dx >= e2.Dx) then
    SetOutrecClockwise(outRec, e1,e2) else
    SetOutrecCounterClockwise(outRec, e1,e2);

  new(op);
  op.Pt := pt;
  op.Next := op;
  op.Prev := op;
  outRec.Pts := op;
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

procedure TClipper2.AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64);
begin
  AddOutPt(e1, pt);
  if  (e1.OutRec = e2.OutRec) then EndOutRec(e1.OutRec)
  //and to preserve the winding orientation of Outrec ...
  else if e1.OutRec.Idx < e2.OutRec.Idx then
    JoinOutrecPaths(e1, e2) else
    JoinOutrecPaths(e2, e1);
end;
//------------------------------------------------------------------------------

procedure ReversePolyPtLinks(pp: POutPt); {$IFDEF INLINING} inline; {$ENDIF}
var
  pp1, pp2: POutPt;
begin
  if (pp.Next = pp.Prev) then Exit;
  pp1 := pp;
  repeat
    pp2:= pp1.Next;
    pp1.Next := pp1.Prev;
    pp1.Prev := pp2;
    pp1 := pp2;
  until pp1 = pp;
end;
//------------------------------------------------------------------------------

procedure TClipper2.JoinOutrecPaths(e1, e2: PActive);
var
  p1_start, p1_end, p2_start, p2_end: POutPt;
begin
  //join e2 outrec path onto e1 outrec path and then delete e2 outrec path
  //pointers. (nb: Only very rarely do the joining ends share the same coords.)
  p1_start :=  e1.OutRec.Pts;
  p2_start :=  e2.OutRec.Pts;
  p1_end := p1_start.Prev;
  p2_end := p2_start.Prev;
  if IsStartSide(e1) then
  begin
    if IsStartSide(e2) then
    begin
      //start-start join
      ReversePolyPtLinks(p2_start);
      p2_start.Next := p1_start;
      p1_start.Prev := p2_start;
      p1_end.Next := p2_end; //P2 now reversed
      p2_end.Prev := p1_end;
      e1.OutRec.Pts := p2_end;
      e1.OutRec.StartE := e2.OutRec.EndE;
    end else
    begin
      //end-start join
      p2_end.Next := p1_start;
      p1_start.Prev := p2_end;
      p2_start.Prev := p1_end;
      p1_end.Next := p2_start;
      e1.OutRec.Pts := p2_start;
      e1.OutRec.StartE := e2.OutRec.StartE;
    end;
    if assigned(e1.OutRec.StartE) then //ie closed path
      e1.OutRec.StartE.OutRec := e1.OutRec;
  end else
  begin
    if IsStartSide(e2) then
    begin
      //end-start join (see JoinOutrec3.png)
      p1_end.Next := p2_start;
      p2_start.Prev := p1_end;
      p1_start.Prev := p2_end;
      p2_end.Next := p1_start;
      e1.OutRec.EndE := e2.OutRec.EndE;
    end else
    begin
      //end-end join (see JoinOutrec4.png)
      ReversePolyPtLinks(p2_start);
      p1_end.Next := p2_end; //P2 now reversed
      p2_end.Prev := p1_end;
      p2_start.Next := p1_start;
      p1_start.Prev := p2_start;
      e1.OutRec.EndE := e2.OutRec.StartE;
    end;
    if assigned(e1.OutRec.EndE) then //ie closed path
      e1.OutRec.EndE.OutRec := e1.OutRec;
  end;

  if e1.OutRec.Owner = e2.OutRec then
    raise EClipperLibException.Create(rsClippingErr);

  //after joining, the e2.OutRec contains not vertices ...
  e2.OutRec.StartE := nil;
  e2.OutRec.EndE := nil;
  e2.OutRec.Pts := nil;
  e2.OutRec.Owner := e1.OutRec; //this may be redundant

  //and e1 and e2 are maxima and are about to be dropped from the Actives list.
  e1.OutRec := nil;
  e2.OutRec := nil;
end;
//------------------------------------------------------------------------------

procedure TerminateHotOpen(e: PActive);
begin
  if e.OutRec.StartE = e then
    e.OutRec.StartE := nil else
    e.OutRec.EndE := nil;
  e.OutRec := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper2.SwapOutRecs(e1, e2: PActive);
var
  or1, or2: POutRec;
  e: PActive;
begin
  or1 := e1.OutRec;
  or2 := e2.OutRec;
  if (or1 = or2) then
  begin
    e := or1.StartE;
    or1.StartE := or1.EndE;
    or1.EndE := e;
    Exit;
  end;
  if assigned(or1) then
  begin
    if e1 = or1.StartE then
      or1.StartE := e2 else
      or1.EndE := e2;
  end;
  if assigned(or2) then
  begin
    if e2 = or2.StartE then
      or2.StartE := e1 else
      or2.EndE := e1;
  end;
  e1.OutRec := or2;
  e2.OutRec := or1;
end;
//------------------------------------------------------------------------------

procedure TClipper2.AddOutPt(e: PActive; const pt: TPoint64);
var
  opStart, opEnd, opNew: POutPt;
  toStart: Boolean;
begin
  //Outrec.Pts: a circular double-linked-list of POutPt.
  toStart := IsStartSide(e);
  opStart := e.OutRec.Pts;
  opEnd := opStart.Prev;
  if toStart then
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
  if toStart then
    e.OutRec.Pts := opNew;
end;
//------------------------------------------------------------------------------

procedure TClipper2.PushHorz(e: PActive);
begin
  if assigned(FSel) then
    e.NextInSEL := FSel else
    e.NextInSEL := nil;
  FSel := e;
end;
//------------------------------------------------------------------------------

function TClipper2.PopHorz(out e: PActive): Boolean;
begin
  result := assigned(FSel);
  if not result then Exit;
  e := FSel;
  FSel := FSel.NextInSEL;
end;
//------------------------------------------------------------------------------

procedure TClipper2.StartOpenPath(e: PActive; const pt: TPoint64);
var
  OutRec: POutRec;
  op    : POutPt;
begin
  new(OutRec);
  OutRec.Idx := FOutRecList.Add(OutRec);
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

procedure TClipper2.UpdateEdgeIntoAEL(var e: PActive);
begin
  e.Bot := e.Top;
  e.vertTop := NextVertex(e);
  e.Top := e.vertTop.Pt;
  e.Curr := e.Bot;
  SetDx(e);
  if not IsHorizontal(e) then InsertScanLine(e.Top.Y);
end;
//------------------------------------------------------------------------------

procedure TClipper2.IntersectEdges(e1, e2: PActive; pt: TPoint64);
var
  e1Contributing, e2contributing: Boolean;
  e1WindCnt, e2WindCnt, e1WindCnt2, e2WindCnt2: integer;
begin
  //e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
  //e2 in AEL except when e1 is being inserted at the intersection point ...

  e1Contributing := IsHotEdge(e1);
  e2contributing := IsHotEdge(e2);

  e1.Curr := pt;
  e2.Curr := pt;

  //if either edge is on an OPEN path ...
  if FHasOpenPaths and (IsOpen(e1) or IsOpen(e2)) then
  begin

    //ignore subject-subject open path intersections,
    //unless they're the same OutRec and hence need joining ...
    if IsOpen(e1) AND IsOpen(e2) then
    begin
      if e1Contributing and (e1.OutRec = e2.OutRec) then
      AddLocalMaxPoly(e1, e2, pt);
      Exit;
    end

    //if intersecting a subj line with a subj poly ...
    else if IsSamePolyType(e1, e2) and
      (e1.WindDx <> e2.WindDx) and (FClipType = ctUnion) then
    begin
      if IsOpen(e1) then
      begin
        if (e2contributing) then
        begin
          if e1Contributing then AddOutPt(e1, pt)
          else StartOpenPath(e1, pt);
          if (e1Contributing) then TerminateHotOpen(e1);
        end;
      end else
      begin
        if (e1Contributing) then
        begin
          if e2contributing then AddOutPt(e2, pt)
          else StartOpenPath(e2, pt);
          if (e2contributing) then TerminateHotOpen(e2);
        end;
      end;
    end
    else if not IsSamePolyType(e1, e2) then
    begin
      //toggle subj open path OutIdx on/off when Abs(clip.WndCnt) = 1 ...
      if IsOpen(e1) and (Abs(e2.WindCnt) = 1) and
       ((FClipType <> ctUnion) or (e2.WindCnt2 = 0)) then
      begin
        if e1Contributing then AddOutPt(e1, pt)
        else StartOpenPath(e1, pt);
        if e1Contributing then TerminateHotOpen(e1);
      end
      else if IsOpen(e2) and (Abs(e1.WindCnt) = 1) and
       ((FClipType <> ctUnion) or (e1.WindCnt2 = 0)) then
      begin
        if e2contributing then AddOutPt(e2, pt)
        else StartOpenPath(e2, pt);
        if e2contributing then TerminateHotOpen(e2);
      end
    end;
    Exit;
  end;

  //update winding counts...
  //assumes that e1 will be to the right of e2 ABOVE the intersection
  if IsSamePolyType(e1, e2) then
  begin
    if FFillType = ftEvenOdd then
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
    if FFillType <> ftEvenOdd then Inc(e1.WindCnt2, e2.WindDx)
    else if e1.WindCnt2 = 0 then e1.WindCnt2 := 1
    else e1.WindCnt2 := 0;

    if FFillType <> ftEvenOdd then Dec(e2.WindCnt2, e1.WindDx)
    else if e2.WindCnt2 = 0 then e2.WindCnt2 := 1
    else e2.WindCnt2 := 0;
  end;

  case FFillType of
    ftPositive:
      begin
        e1WindCnt := e1.WindCnt;
        e2WindCnt := e2.WindCnt;
      end;
    ftNegative:
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

  if e1Contributing and e2contributing then
  begin
    if not (e1WindCnt in [0,1]) or not (e2WindCnt in [0,1]) or
      (not IsSamePolyType(e1, e2) and (fClipType <> ctXor)) then
    begin
      AddLocalMaxPoly(e1, e2, pt);
    end
    else if (e1.OutRec = e2.OutRec) then //optional
    begin
      AddLocalMaxPoly(e1, e2, pt);
      AddLocalMinPoly(e1, e2, pt);
    end else
    begin
      AddOutPt(e1, pt);
      AddOutPt(e2, pt);
      SwapOutRecs(e1, e2);
    end;
  end else if e1Contributing then
  begin
    if (e2WindCnt = 0) or (e2WindCnt = 1) then
    begin
      AddOutPt(e1, pt);
      SwapOutRecs(e1, e2);
    end;
  end
  else if e2contributing then
  begin
    if (e1WindCnt = 0) or (e1WindCnt = 1) then
    begin
      AddOutPt(e2, pt);
      SwapOutRecs(e1, e2);
    end;
  end
  else if  ((e1WindCnt = 0) or (e1WindCnt = 1)) and ((e2WindCnt = 0) or (e2WindCnt = 1)) then
  begin
    //neither Edge is currently contributing ...
    case FFillType of
      ftPositive:
      begin
        e1WindCnt2 := e1.WindCnt2;
        e2WindCnt2 := e2.WindCnt2;
      end;
      ftNegative:
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
          if ((e1.LocMin.PolyType = ptClip) and (e1WindCnt2 > 0) and
            (e2WindCnt2 > 0)) or ((e1.LocMin.PolyType = ptSubject) and
            (e1WindCnt2 <= 0) and (e2WindCnt2 <= 0)) then
              AddLocalMinPoly(e1, e2, pt);
        ctXor:
          AddLocalMinPoly(e1, e2, pt);
      end
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.DeleteFromAEL(e: PActive);
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
  e.NextInAEL := nil;
  e.PrevInAEL := nil;
  Dispose(e);
end;
//------------------------------------------------------------------------------

procedure TClipper2.CopyActivesToSEL;
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

function TClipper2.ExecuteInternal(clipType: TClipType; fillType: TFillType): Boolean;
var
  Y: Int64;
  e: PActive;
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
      while PopHorz(e) do ProcessHorizontal(e);
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

function TClipper2.Execute(clipType: TClipType; out closedPaths: TPaths;
  fillType: TFillType): Boolean;
var
  dummy: TPaths;
begin
  closedPaths := nil;
  try
    Result := ExecuteInternal(clipType, fillType);
    if Result then BuildResult(closedPaths, dummy);
  finally
    CleanUp;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.Execute(clipType: TClipType; out closedPaths, openPaths: TPaths;
  fillType: TFillType = ftEvenOdd): Boolean;
begin
  closedPaths := nil;
  openPaths := nil;
  try
    Result := ExecuteInternal(clipType, fillType);
    if Result then BuildResult(closedPaths, openPaths);
  finally
    CleanUp;
  end;
end;
//------------------------------------------------------------------------------

function TClipper2.Execute(clipType: TClipType; var polytree: TPolyTree;
  out openPaths: TPaths; fillType: TFillType): Boolean;
begin
  if not assigned(polytree) then
    raise EClipperLibException.Create(rsPolyTreeErr);
  polytree.Clear;
  openPaths := nil;
  try
    Result := ExecuteInternal(clipType, fillType);
    if Result then BuildResult2(polytree, openPaths);
  finally
    CleanUp;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessIntersections(const topY: Int64);
begin
  try
    BuildIntersectList(topY);
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
  i: integer;
begin
  for i := 0 to FIntersectList.Count - 1 do
    Dispose(PIntersectNode(FIntersectList[i]));
  FIntersectList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper2.BuildIntersectList(const topY: Int64);
var
  e, eNext: PActive;
  pt: TPoint64;
  isModified: Boolean;
  node: PIntersectNode;
begin
  if not Assigned(FActives) then Exit;

  //copy AEL to SEL while also adjusting Curr.X ...
  FSel := FActives;
  e := FActives;
  while Assigned(e) do
  begin
    e.PrevInSEL := e.PrevInAEL;
    e.NextInSEL := e.NextInAEL;
    e.Curr.X := TopX(e, topY);
    e := e.NextInAEL;
  end;

  //bubblesort (because adjacent swaps are required) ...
  repeat
    isModified := False;
    e := FSel;
    while Assigned(e.NextInSEL) do
    begin
      eNext := e.NextInSEL;
      if (e.Curr.X > eNext.Curr.X) then
      begin
        //An intersection is occuring somewhere within the scanbeam ...
        pt := GetIntersectPoint(e, eNext);

        //Rounding errors can occasionally place the calculated intersection
        //point either below or above the scanbeam, so check and correct ...
        if (pt.Y > e.Curr.Y) then
        begin
          pt.Y := e.Curr.Y;      //E.Curr.Y is still the bottom of scanbeam
          //use the more vertical of the 2 edges to derive pt.X ...
          if (abs(e.Dx) < abs(eNext.Dx)) then
            pt.X := TopX(e, pt.Y) else
            pt.X := TopX(eNext, pt.Y);
        end
        else if pt.Y < topY then
        begin
          pt.Y := topY;          //TopY = top of scanbeam
          if e.Top.Y = topY then
            pt.X := e.Top.X
          else if eNext.Top.Y = topY then
            pt.X := eNext.Top.X
          else if (abs(e.Dx) < abs(eNext.Dx)) then
            pt.X := e.Curr.X
          else
            pt.X := eNext.Curr.X;
        end;

        new(node);
        node.Edge1 := e;
        node.Edge2 := eNext;
        node.Pt := pt;
        FIntersectList.Add(node);

        SwapPositionsInSEL(e, eNext);
        isModified := True;
      end else
        e := eNext;
    end;
    if Assigned(e.PrevInSEL) then
      e.PrevInSEL.NextInSEL := nil
    else Break;
  until not isModified;
end;
//------------------------------------------------------------------------------

procedure TClipper2.ProcessIntersectList;
var
  i: integer;
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

function EdgesAdjacent(node: PIntersectNode): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (node.Edge1.NextInSEL = node.Edge2) or
    (node.Edge1.PrevInSEL = node.Edge2);
end;
//------------------------------------------------------------------------------

function IntersectListSort(node1, node2: Pointer): integer;
var
  i: Int64;
begin
  i := PIntersectNode(node2).Pt.Y - PIntersectNode(node1).Pt.Y;
  if i < 0 then Result := -1
  else if i > 0 then Result := 1
  else Result := 0;
end;
//------------------------------------------------------------------------------

procedure TClipper2.FixupIntersectionOrder;
var
  i, j, cnt: integer;
  node: PIntersectNode;
begin
  //Intersections have been sorted so the bottom-most are processed first but
  //it's also crucial that intersections are made between adjacent edges, so
  //the order of these intersections may need some adjusting ...
  cnt := FIntersectList.Count;
  if cnt < 3 then exit; //any edges must be adjacent :)

  CopyActivesToSEL;
  FIntersectList.Sort(IntersectListSort);
  for i := 0 to cnt - 1 do
  begin
    if not EdgesAdjacent(FIntersectList[i]) then
    begin
      j := i + 1;
      while (j < cnt) and not EdgesAdjacent(FIntersectList[j]) do inc(j);
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

procedure TClipper2.SwapPositionsInAEL(e1, e2: PActive);
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

procedure TClipper2.SwapPositionsInSEL(e1, e2: PActive);
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

procedure TClipper2.ProcessHorizontal(horzEdge: PActive);
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
      //break if we've gone past the end of the horizontal ...
      if (isLeftToRight and (e.Curr.X > horzRight)) or
        (not isLeftToRight and (e.Curr.X < horzLeft)) then break;
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
          AddLocalMaxPoly(horzEdge, e, horzEdge.Top);
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
    if NextVertex(horzEdge).Pt.Y <> horzEdge.Top.Y then Break;

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

  if IsOpen(horzEdge) then
  begin
    if not IsMaxima(horzEdge) then
      UpdateEdgeIntoAEL(horzEdge)
    else if assigned(maxPair) then
          AddLocalMaxPoly(horzEdge, maxPair, horzEdge.Top)
    else
      DeleteFromAEL(horzEdge);
  end else
    UpdateEdgeIntoAEL(horzEdge); //this is the end of an intermediate horiz.
end;
//------------------------------------------------------------------------------

procedure TClipper2.DoTopOfScanbeam(Y: Int64);
var
  e: PActive;
begin
  e := FActives;
  while Assigned(e) do
  begin
    //nb: E will never be horizontal at this point
    if (e.Top.Y = Y) then
    begin
      e.Curr := e.Top; //needed for horizontal processing
      if IsMaxima(e) then
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

function PointCount(pts: POutPt): integer; {$IFDEF INLINING} inline; {$ENDIF}
var
  p: POutPt;
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

procedure TClipper2.BuildResult(out closedPaths, openPaths: TPaths);
var
  i, j, cnt, cntClosed, cntOpen: integer;
  outRec: POutRec;
  op: POutPt;
begin
  cntClosed := 0;
  cntOpen := 0;
  SetLength(closedPaths, FOutRecList.Count);
  SetLength(openPaths, FOutRecList.Count);
  for i := 0 to FOutRecList.Count -1 do
    if Assigned(FOutRecList[i]) then
    begin
      outRec := FOutRecList[i];
      if not assigned(outRec.Pts) then Continue;

      op := outRec.Pts.Prev;
      cnt := PointCount(op);
      //fixup for duplicate start and end points ...
      if PointsEqual(op.Pt, outRec.Pts.Pt) then dec(cnt);

      if (orOpen in outRec.Flags) then
      begin
        if (Cnt < 2) then Continue;
        SetLength(openPaths[cntOpen], cnt);
        for j := 0 to cnt -1 do
        begin
          openPaths[cntOpen][j] := op.Pt;
          op := op.Prev;
        end;
        Inc(cntOpen);
      end else
      begin
        if (Cnt < 3) then Continue;
        SetLength(closedPaths[cntClosed], cnt);
        for j := 0 to cnt -1 do
        begin
          closedPaths[cntClosed][j] := op.Pt;
          op := op.Prev;
        end;
        Inc(cntClosed);
      end;

    end;
  SetLength(closedPaths, cntClosed);
  SetLength(openPaths, cntOpen);
end;
//------------------------------------------------------------------------------

procedure TClipper2.BuildResult2(polyTree: TPolyTree; out openPaths: TPaths);
var
  i, j, cnt, cntOpen: integer;
  outRec: POutRec;
  op: POutPt;
  path: TPath;
begin
  setLength(openPaths, FOutRecList.Count);
  cntOpen := 0;
  for i := 0 to FOutRecList.Count -1 do
    if Assigned(FOutRecList[i]) then
    begin
      outRec := FOutRecList[i];
      if not assigned(outRec.Pts) then Continue;

      op := outRec.Pts.Prev;
      cnt := PointCount(op);
      //avoid duplicate start and end points ...
      if PointsEqual(op.Pt, outRec.Pts.Pt) then dec(cnt);

      if (cnt < 3) then
      begin
        if not (orOpen in outRec.Flags) or (cnt < 2) then Continue;
      end;

      SetLength(path, cnt);
      for j := 0 to cnt -1 do
      begin
        path[j] := op.Pt;
        op := op.Prev;
      end;

      if orOpen in outRec.Flags then
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

function TClipper2.GetBounds: TRect64;
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
  i: integer;
begin
  for i := 0 to FChildList.Count -1 do
    TPolyPath(FChildList[i]).Free;
  FChildList.Clear;
end;
//------------------------------------------------------------------------------

function  TPolyPath.GetChild(index: integer): TPolyPath;
begin
  if (index < 0) or (index >= FChildList.Count) then
    REsult := nil else
    Result := TPolyPath(FChildList[index]);
end;
//------------------------------------------------------------------------------

function  TPolyPath.IsHoleNode: boolean;
begin
  result := not assigned(FParent) or not FParent.IsHoleNode;
end;
//------------------------------------------------------------------------------

function  TPolyPath.GetChildCnt: integer;
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

