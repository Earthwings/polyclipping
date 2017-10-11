unit ClipperTri;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  11 October 2017                                                 *
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

{$IFDEF DEBUG}
  {$UNDEF INLINING}
{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Clipper;

type
  TClipperTri = class(TClipper)
  private
    FMaxMin: Boolean;
    FTriSolution: TPaths;
    procedure DeleteBadLocalMinima(leftB, rightB: PActive);
    procedure AddPolygon(const pt1, pt2, pt3: TPoint64);
    procedure TriangulateLeft(e: PActive);
    procedure TriangulateRight(e: PActive);
    procedure BuildResult(out closedPaths: TPaths);
  protected
    procedure IntersectEdges(e1, e2: PActive; pt: TPoint64); override;
    procedure SwapOutRecs(e1, e2: PActive); override;
    procedure AddOutPt(e: PActive; const pt: TPoint64); override;
    procedure AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64); override;
    procedure AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64); override;
    procedure InsertLocalMinimaIntoAEL(const botY: Int64); override;
  public
    function Execute(clipType: TClipType; out closedPaths: TPaths;
      fillRule: TFillRule = frEvenOdd): Boolean; override;
  end;

implementation

type
  POutRecTri = ^TOutRecTri;
  TOutRecFill = (ofInternal, ofExternal);

  //OutRecTri: contains a path in the clipping solution. Edges in the AEL will
  //carry a pointer to an OutRec when they are part of the clipping solution.
  //While both the Clipper OutRec and TriOutRec trace two bounds via two active
  //edges, the TriOutRec used separate POutPts for each edge ...
  TOutRecTri = record
    Idx      : Integer;
    Edges    : array [0..1] of PActive;
    OutPts   : array [0..1] of POutPt;
  end;

const
  HORIZONTAL = NegInfinity;

{$OVERFLOWCHECKS OFF}

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

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

function ZeroArea(const pt1, pt2, pt3: TPoint64): Boolean;
begin
  Result := (pt1.x * (pt2.y - pt3.y) +
    pt2.x * (pt3.y - pt1.y) + pt3.x * (pt1.y - pt2.y)) = 0;
end;
//------------------------------------------------------------------------------

function IsHotEdge(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := assigned(e.OutRec);
end;
//------------------------------------------------------------------------------

function IsStartSide(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (e = POutRecTri(e.OutRec).Edges[0]);
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

function GetIsOuter(e: PActive): Boolean;
begin
  //nb: there are no holes with triangulation, but edges still represent either
  //inner or outer polygon boundaries. Here, IsOuter simply means that the
  //local minima appears to start outside other polgyons and that 'filling'
  //will be inside the minima rather than around it. Consequently, edges
  //must alternate the IsOuter flag from left to right across the AEL.
  if IsHorizontal(e) and (e.Top.X < e.Bot.X) then
  begin
    e := e.NextInAEL;
    while assigned(e) and not IsHotEdge(e) do e := e.NextInAEL;
    if not assigned(e) then Result := true
    else Result := IsStartSide(e);
  end else
  begin
    e := e.PrevInAEL;
    while true do
    begin
      while assigned(e) and not IsHotEdge(e) do e := e.PrevInAEL;
      if not assigned(e) then Result := true
//      else if IsHorizontal(e) and (e.Bot.X < e.Top.X) then
//      begin
//        e := e.PrevInAEL;
//        Continue;
//      end
      else Result := not IsStartSide(e);
      break;
    end;
  end;
end;
//------------------------------------------------------------------------------

function GetTopOutPt(e: PActive): POutPt; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if IsStartSide(e) then
    Result := POutRecTri(e.OutRec).OutPts[0] else
    Result := POutRecTri(e.OutRec).OutPts[1];
end;
//------------------------------------------------------------------------------

function CrossProduct(const pt1, pt2, pt3: TPoint64): Int64;
begin
  //todo: this will be problematic with very large int64 coords
  result := ((pt2.x-pt1.x) * (pt1.y-pt3.y) - (pt1.x-pt3.x) * (pt2.y-pt1.y))
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
      Result := e2.Curr.X <= e1.Curr.X;
end;
//----------------------------------------------------------------------

procedure SetDx(e: PActive);  {$IFDEF INLINING} inline; {$ENDIF}
var
  dy: Int64;
begin
  dy := (e.Top.Y - e.Bot.Y);
  if dy = 0 then e.dx := HORIZONTAL
  else e.Dx := (e.Top.X - e.Bot.X)/dy;
end;
//------------------------------------------------------------------------------

procedure DeleteVertex(v: PVertex);
var
  pv, nv: PVertex;
begin
  pv := v.prev;
  nv := v.next;
  pv.next := nv;
  nv.prev := pv;
end;
//------------------------------------------------------------------------------

function IsMaxima(e: PActive): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := vfLocMax in e.vertTop.flags;
end;
//------------------------------------------------------------------------------

procedure DisposeOutPt(pp: POutPt);  {$IFDEF INLINING} inline; {$ENDIF}
begin
  //be careful that pp isn't OutRec.Pts nor that pp = pp.Next;
  if assigned(pp.Prev) then pp.Prev.Next := pp.Next;
  if assigned(pp.Next) then pp.Next.Prev := pp.Prev;
  Dispose(pp);
end;
//------------------------------------------------------------------------------

procedure DisposeOutPts(pp: POutPt);  {$IFDEF INLINING} inline; {$ENDIF}
var
  tmpPp: POutPt;
begin
  while Assigned(pp) do
  begin
    tmpPp := pp;
    pp := pp.Prev;
    dispose(tmpPp);
  end;
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

procedure SetOutrecClockwise(outRec: POutRecTri; e1, e2: PActive);
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  outRec.Edges[0] := e1;
  outRec.Edges[1] := e2;
  e1.OutRec := POutRec(outRec);
  e2.OutRec := POutRec(outRec);
end;
//------------------------------------------------------------------------------

procedure SetOutrecCounterClockwise(outRec: POutRecTri; e1, e2: PActive);
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  outRec.Edges[0] := e2;
  outRec.Edges[1] := e1;
  e1.OutRec := POutRec(outRec);
  e2.OutRec := POutRec(outRec);
end;

//------------------------------------------------------------------------------
// TClipperTri methods ...
//------------------------------------------------------------------------------

procedure TClipperTri.DeleteBadLocalMinima(leftB, rightB: PActive);
var
  e: PActive;
begin
  //nb: leftB.WindDx is always < 0 here.
  DeleteVertex(leftB.vertTop.next);          //this deletes the minima
  InsertScanLine(leftB.Top.Y);
  if rightB.Top.Y > leftB.Top.Y then e := rightB else e := leftB;
  if IsMaxima(e) then
  begin
    e.vertTop.flags := [];                   //just remove maxima flag
  end else
  begin
    leftB.LocMin.vertex := e.vertTop;
    LocMinList.Sort(LocMinListSort);
    CurrentLocMinIdx := CurrentLocMinIdx -1; //reinsert the adjusted LocMin
  end;
  Dispose(leftB);
  Dispose(rightB);
end;
//----------------------------------------------------------------------

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

procedure TClipperTri.IntersectEdges(e1, e2: PActive; pt: TPoint64);
var
  e1WindCnt, e2WindCnt, e1WindCnt2, e2WindCnt2: Integer;
begin
  e1.Curr := pt;
  e2.Curr := pt;

  //update winding counts...
  //assumes that e1 will be to the right of e2 ABOVE the intersection
  if IsSamePolyType(e1, e2) then
  begin
    if FillRule = frEvenOdd then
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
    if FillRule <> frEvenOdd then Inc(e1.WindCnt2, e2.WindDx)
    else if e1.WindCnt2 = 0 then e1.WindCnt2 := 1
    else e1.WindCnt2 := 0;

    if FillRule <> frEvenOdd then Dec(e2.WindCnt2, e1.WindDx)
    else if e2.WindCnt2 = 0 then e2.WindCnt2 := 1
    else e2.WindCnt2 := 0;
  end;

  case FillRule of
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
      (not IsSamePolyType(e1, e2) and (ClipType <> ctXor)) then
    begin
      AddLocalMaxPoly(e1, e2, pt);
    end else
    begin
      AddLocalMaxPoly(e1, e2, pt);
      FMaxMin := true;
      AddLocalMinPoly(e1, e2, pt); //#4, #111
      FMaxMin := false;
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
  else if ((e1WindCnt = 0) or (e1WindCnt = 1)) and
    ((e2WindCnt = 0) or (e2WindCnt = 1)) then
  begin
    //neither Edge is currently contributing ...
    case FillRule of
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
      case ClipType of
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

procedure TClipperTri.InsertLocalMinimaIntoAEL(const botY: Int64);

  procedure InsertEdgeIntoAEL(e, e2: PActive);
  begin
    if not Assigned(FActives) then
    begin
      e.PrevInAEL := nil;
      e.NextInAEL := nil;
      FActives := e;
    end else
    begin
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
      end else
      begin
        while Assigned(e2.NextInAEL) and
          E2InsertsBeforeE1(e, e2.NextInAEL, true) do
            e2 := e2.NextInAEL;
      end;
      e.NextInAEL := e2.NextInAEL;
      if Assigned(e2.NextInAEL) then
        e2.NextInAEL.PrevInAEL := e;
      e.PrevInAEL := e2;
      e2.NextInAEL := e;
    end;
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

    if IsHorizontal(leftB) then
    begin
      if (leftB.Top.X > leftB.Bot.X) then SwapActives(leftB, rightB);
    end
    else if IsHorizontal(rightB) then
    begin
      if (rightB.Top.X < rightB.Bot.X) then SwapActives(leftB, rightB);
    end
    else if (leftB.Dx < rightB.Dx) then SwapActives(leftB, rightB)
    else if (leftB.Dx = rightB.Dx) then
    begin
      DeleteBadLocalMinima(leftB, rightB);
      Continue;
    end;

    InsertEdgeIntoAEL(leftB, nil);      //insert left edge
    SetWindingLeftEdgeClosed(leftB);
    contributing := IsContributingClosed(leftB);

    rightB.WindCnt := leftB.WindCnt;
    rightB.WindCnt2 := leftB.WindCnt2;
    InsertEdgeIntoAEL(rightB, leftB);   //insert right edge
    if contributing then
      AddLocalMinPoly(leftB, rightB, leftB.Bot);

    if IsHorizontal(rightB) then
      PushHorz(rightB) else
      InsertScanLine(rightB.Top.Y);

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

  end; //while PopLocalMinima
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddPolygon(const pt1, pt2, pt3: TPoint64);
var
  i: integer;
  path: TPath;
begin
  if ZeroArea(pt1, pt2, pt3) then exit;
  setLength(path, 3);
  path[0] := pt1; path[1] := pt2; path[2] := pt3;
  i := Length(FTriSolution);
  setLength(FTriSolution, i +1);
  FTriSolution[i] := path;
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddLocalMinPoly(e1, e2: PActive; const pt: TPoint64);
var
  outRec: POutRecTri;
  op, op1, op2: POutPt;
  eLeft, eRight: PActive;
  isOuter: Boolean;
begin
  new(POutRec(outRec));
  outRec.Idx := OutRecList.Add(outRec);
  isOuter := GetIsOuter(e1);

  //now set orientation ...
  if IsHorizontal(e1) then
  begin
    if IsHorizontal(e2) then
    begin
      if isOuter = (e1.Bot.X > e2.Bot.X) then
        SetOutrecClockwise(outRec, e1, e2) else
        SetOutrecCounterClockwise(outRec, e1, e2);
    end
    else if isOuter = (e1.Top.X < e1.Bot.X) then
      SetOutrecClockwise(outRec, e1, e2) else
      SetOutrecCounterClockwise(outRec, e1, e2);
  end
  else if IsHorizontal(e2) then
  begin
    if isOuter = (e2.Top.X > e2.Bot.X) then
      SetOutrecClockwise(outRec, e1,e2) else
      SetOutrecCounterClockwise(outRec, e1,e2);
  end
  else if isOuter = (e1.Dx >= e2.Dx) then
    SetOutrecClockwise(outRec, e1,e2) else
    SetOutrecCounterClockwise(outRec, e1,e2);

  new(op);
  op.isMax := false;
  op.Pt := pt;
  op.Next := nil;
  op.Prev := nil;
  outRec.OutPts[0] := op;

  new(op);
  op.isMax := false;
  op.Pt := pt;
  op.Next := nil;
  op.Prev := nil;
  outRec.OutPts[1] := op;

  if isOuter or FMaxMin then Exit;

  eLeft := GetLeftAdjacentHotEdge(e1);
  if not assigned(eLeft) then raise Exception.Create('oops');
  op1 := GetTopOutPt(eLeft);
  while assigned(op1.Prev) do op1 := op1.Prev;
  eRight := GetRightAdjacentHotEdge(e2);
  if not assigned(eRight) then Exit; //sitting on an ltor horizontal
  op2 := GetTopOutPt(eRight);
  while assigned(op2.Prev) do op2 := op2.Prev;
  AddPolygon(op1.Pt, op.pt, op2.Pt);

  TriangulateLeft(e1);
  TriangulateRight(e2);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.TriangulateLeft(e: PActive);
var
  e2: PActive;
  op1, op2, tmp, tmp2: POutpt;
  cpVal: Int64;
  op1TrimNeeded: Boolean;
begin
  //let op1 be the top OutPt of the current edge (e) and let op2 be the
  //top OutPt of the first Hot edge to the left (e2) ...

  op1 := GetTopOutPt(e);
  //first, using op1, try to tidy up pending polygons under op1 (top down) ...
  while assigned(op1.Prev) and assigned(op1.Prev.Prev) do
  begin
    cpVal := CrossProduct(op1.Pt, op1.Prev.Pt, op1.Prev.Prev.Pt);
    if cpVal > 0 then break;
    if (cpVal < 0) then AddPolygon(op1.Pt, op1.Prev.Pt, op1.Prev.Prev.Pt);
    DisposeOutPt(op1.Prev);
  end;

  e2 := GetLeftAdjacentHotEdge(e);
  if not assigned(e2) then Exit; //?? error

  //next tidy up remaining polygons under op1 (bottom-up) using the
  //lower-most pending OutPt under op2 ...
  op2 := GetTopOutPt(e2);
  tmp2 := op2;
  while assigned(tmp2.Prev) do tmp2 := tmp2.Prev;
  tmp := op1;
  while assigned(tmp.Prev) do tmp := tmp.Prev;
  while (tmp <> op1) do
  begin
      cpVal := CrossProduct(tmp.Next.Pt, tmp.Pt, tmp2.pt);
    if (cpVal > 0) then break;
    if (cpVal < 0) then
      AddPolygon(tmp2.pt, tmp.Pt, tmp.Next.Pt);
    tmp := tmp.Next;
    DisposeOutPt(tmp.Prev);
  end;

  if assigned(op1.Prev) and op1.Prev.isMax then
    DisposeOutPt(op1.Prev);

  //finally tidy up polygons under op2 (bottom-up) using op1 ...
  if not assigned(op2.Prev) then Exit;
  op1TrimNeeded := false;
  while (tmp2 <> op2) and (CrossProduct(op1.pt, tmp2.Pt, tmp2.Next.Pt) <= 0) do
  begin
    AddPolygon(op1.pt, tmp2.Pt, tmp2.Next.Pt);
    tmp2 := tmp2.Next;
    DisposeOutPt(tmp2.Prev);
    op1TrimNeeded := true;
  end;
  if op1TrimNeeded then
    while assigned(op1.Prev) do DisposeOutPt(op1.Prev);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.TriangulateRight(e: PActive);
var
  e2: PActive;
  op1, op2, tmp, tmp2: POutpt;
  cpVal: Int64;
  op1TrimNeeded: Boolean;
begin

  //let op1 be the top OutPt of the current edge (e) and let op2 be the
  //top OutPt of the first Hot edge to the right (e2) ...

  op1 := GetTopOutPt(e);
  //first, using op1, try to tidy up pending polygons under op1 (top down) ...
  while assigned(op1.Prev) and assigned(op1.Prev.Prev) do
  begin
    cpVal := CrossProduct(op1.Pt, op1.Prev.Pt, op1.Prev.Prev.Pt);
    if (cpVal < 0) then break;
    if (cpVal > 0) then AddPolygon(op1.Pt, op1.Prev.Pt, op1.Prev.Prev.Pt);
    DisposeOutPt(op1.Prev);
  end;

  e2 := GetRightAdjacentHotEdge(e);
  if not assigned(e2) then Exit; //?? error

  //next tidy up remaining polygons under op1 (bottom-up) using the
  //lower-most pending OutPt under op2 ...
  op2 := GetTopOutPt(e2);
  tmp2 := op2;
  while assigned(tmp2.Prev) do tmp2 := tmp2.Prev;
  tmp := op1;
  while assigned(tmp.Prev) do tmp := tmp.Prev;
  if PointsEqual(tmp.Pt, tmp2.Pt) then
  begin
    while assigned(op1.Prev) do DisposeOutPt(op1.Prev); //#2 test
  end else
  begin
    while (tmp <> op1) do
    begin
      cpVal := CrossProduct(tmp.Next.Pt, tmp.Pt, tmp2.pt);
      if (cpVal < 0) then break;
      if (cpVal > 0) then
        AddPolygon(tmp2.pt, tmp.Pt, tmp.Next.Pt);
      tmp := tmp.Next;
      DisposeOutPt(tmp.Prev);
    end;
  end;

  if assigned(op1.Prev) and op1.Prev.isMax then
    DisposeOutPt(op1.Prev);

  //finally tidy up polygons under op2 (bottom-up) using op1 ...
  if not assigned(op2.Prev) then Exit;

  op1TrimNeeded := false;
  while (tmp2 <> op2) and (CrossProduct(op1.pt, tmp2.Pt, tmp2.Next.Pt) >= 0) do
  begin
    AddPolygon(op1.pt, tmp2.Pt, tmp2.Next.Pt);
    tmp2 := tmp2.Next;
    DisposeOutPt(tmp2.Prev);
    op1TrimNeeded := true;
  end;
  if op1TrimNeeded then
    while assigned(op1.Prev) do DisposeOutPt(op1.Prev);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddLocalMaxPoly(e1, e2: PActive; const pt: TPoint64);
var
  i: integer;
  eLeft, eRight: PActive;
  op, op2, tmp, tmp2: POutPt;
  e1OutRec: POutRecTri;
begin
  AddOutPt(e1, pt);
  AddOutPt(e2, pt);
  //nb: e2's side is USUALLY but not always the opposite of e1, so ...
  if IsStartSide(e2) then i := 0 else i := 1;

  if IsStartSide(e1) then
  begin
    //remove e1.OutRec and fixup e2.OutRec ...
    DisposeOutPts(POutRecTri(e1.OutRec).OutPts[0]);
    DisposeOutPts(POutRecTri(e2.OutRec).OutPts[i]);
    POutRecTri(e2.OutRec).Edges[i] := POutRecTri(e1.OutRec).Edges[1];
    POutRecTri(e2.OutRec).OutPts[i] := POutRecTri(e1.OutRec).OutPts[1];
    POutRecTri(e1.OutRec).Edges[1].OutRec := e2.OutRec;

    POutRecTri(e1.OutRec).Edges[0] := nil;
    POutRecTri(e1.OutRec).Edges[1] := nil;
    POutRecTri(e1.OutRec).OutPts[0] := nil;
    POutRecTri(e1.OutRec).OutPts[1] := nil;
    e1.OutRec := nil;
    e2.OutRec := nil;
    Exit;
  end;

  //nb: it's an inner max to be here so e1 must be the end side
  //and e2 is USUALLY the start.
  e1OutRec := POutRecTri(e1.OutRec);
  eLeft := GetLeftAdjacentHotEdge(e1);
  eRight := GetRightAdjacentHotEdge(e2); //#4

  if not assigned(eLeft) or not assigned(eRight) then
  begin
    DisposeOutPts(POutRecTri(e1.OutRec).OutPts[1]);
    DisposeOutPts(POutRecTri(e2.OutRec).OutPts[i]);
    POutRecTri(e2.OutRec).Edges[i] := POutRecTri(e1.OutRec).Edges[0];
    POutRecTri(e2.OutRec).OutPts[i] := POutRecTri(e1.OutRec).OutPts[0];
    POutRecTri(e1.OutRec).Edges[0].OutRec := e2.OutRec;
    POutRecTri(e1.OutRec).Edges[0] := nil;
    POutRecTri(e1.OutRec).Edges[1] := nil;
    POutRecTri(e1.OutRec).OutPts[0] := nil;
    POutRecTri(e1.OutRec).OutPts[1] := nil;
    e1.OutRec := nil;
    e2.OutRec := nil;
    Exit;
  end;

  op := GetTopOutPt(eLeft);
  while assigned(op.Prev) do op := op.Prev;

  //attach inner pending OutPts in reverse order to left outer edge ...
  tmp := e1OutRec.OutPts[1];

  tmp.isMax := true;
  while assigned(tmp.Prev) do tmp := tmp.Prev;
  while assigned(tmp) do
  begin
    tmp2 := tmp.Next;
    if PointsEqual(op.Pt, tmp.Pt) then
    begin
      DisposeOutPt(tmp);
    end else
    begin
      op.Prev := tmp;
      tmp.Next := op;
      tmp.Prev := nil;
      op := tmp;
    end;
    tmp := tmp2;
  end;
  e1OutRec.OutPts[1] := nil;
  e1OutRec.Edges[1] := nil;

  e1.OutRec := nil;
  op2 := GetTopOutPt(eRight);
  while assigned(op2.Prev) do op2 := op2.Prev;

  //attach inner pending OutPt in reverse order to right outer edge ...
  tmp := POutRecTri(e2.OutRec).OutPts[0];
  tmp.isMax := true;
  while assigned(tmp.Prev) do tmp := tmp.Prev;
  while assigned(tmp) do
  begin
    tmp2 := tmp.Next;
    if PointsEqual(op2.Pt, tmp.Pt) then
    begin
      DisposeOutPt(tmp);
    end else
    begin
      op2.Prev := tmp;
      tmp.Next := op2;
      tmp.Prev := nil;
      op2 := tmp;
    end;
    tmp := tmp2;
  end;

  //remove e1.OutRec and fixup e2.OutRec ...
  POutRecTri(e2.OutRec).Edges[0] := e1OutRec.Edges[0];
  POutRecTri(e2.OutRec).OutPts[0] := e1OutRec.OutPts[0];
  POutRecTri(e1OutRec).Edges[0].OutRec := e2.OutRec;
  e1OutRec.Edges[0] := nil;
  e1OutRec.OutPts[0] := nil;
  e1OutRec.Edges[1] := nil;
  e1OutRec.OutPts[1] := nil;
  e1.OutRec := nil;
  e2.OutRec := nil;
end;
//------------------------------------------------------------------------------

procedure TClipperTri.SwapOutRecs(e1, e2: PActive);
var
  or1, or2: POutRecTri;
  e: PActive;
begin
  or1 := POutRecTri(e1.OutRec);
  or2 := POutRecTri(e2.OutRec);
  if (or1 = or2) then
  begin
    e := or1.Edges[0];
    or1.Edges[0] := or1.Edges[1];
    or1.Edges[1] := e;
    Exit;
  end;
  if assigned(or1) then
  begin
    if e1 = or1.Edges[0] then
      or1.Edges[0] := e2 else
      or1.Edges[1] := e2;
  end;
  if assigned(or2) then
  begin
    if e2 = or2.Edges[0] then
      or2.Edges[0] := e1 else
      or2.Edges[1] := e1;
  end;
  e1.OutRec := POutRec(or2);
  e2.OutRec := POutRec(or1);
end;
//------------------------------------------------------------------------------

procedure TClipperTri.AddOutPt(e: PActive; const pt: TPoint64);
var
  op, opNew: POutPt;
begin
  if IsStartSide(e) then
  begin
    op := POutRecTri(e.OutRec).OutPts[0];
    if PointsEqual(pt, op.Pt) then Exit;
    new(opNew);
    opNew.isMax := false;
    opNew.Pt := pt;
    opNew.Next := nil;
    opNew.Prev := op;
    op.Next := opNew;
    POutRecTri(e.OutRec).OutPts[0] := opNew;
    TriangulateRight(e);
  end else
  begin
    op := POutRecTri(e.OutRec).OutPts[1];
    if PointsEqual(pt, op.Pt) then Exit;
    new(opNew);
    opNew.isMax := false;
    opNew.Pt := pt;
    opNew.Next := nil;
    opNew.Prev := op;
    op.Next := opNew;
    POutRecTri(e.OutRec).OutPts[1] := opNew;
    TriangulateLeft(e);
  end;
end;
//------------------------------------------------------------------------------

function TClipperTri.Execute(clipType: TClipType; out closedPaths: TPaths;
  fillRule: TFillRule): Boolean;
begin
  closedPaths := nil;
  if clipType = ctNone then
    Result := true
  else
    try
      Result := ExecuteInternal(clipType, fillRule);
      if Result then BuildResult(closedPaths);
    finally
      CleanUp;
    end;
end;
//------------------------------------------------------------------------------

function PointCount(pts: POutPt): Integer; {$IFDEF INLINING} inline; {$ENDIF}
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

procedure TClipperTri.BuildResult(out closedPaths: TPaths);
var
  i, cnt: Integer;
begin
  cnt := Length(FTriSolution);
  SetLength(closedPaths, cnt);
  for i := 0 to cnt-1 do
    closedPaths[i] := FTriSolution[i];
end;
//------------------------------------------------------------------------------

end.

