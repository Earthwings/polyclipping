/*******************************************************************************
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (beta)                                                     *
* Date      :  13 Noveber 2017                                                 *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
* Purpose   :  Triangulate clipping solutions                                  *
* License   :  http://www.boost.org/LICENSE_1_0.txt                            *
*******************************************************************************/

using System;
using System.Collections.Generic;
using ClipperLib;

namespace ClipperLib
{
  using Path = List<Point64>;
  using Paths = List<List<Point64>>;


  public class OutPtTri : OutPt
  {
    internal OutRec outrec;
    internal OutRecTri rightOutrec;
  };

  public class OutRecTri : OutRec
  {
    internal OutPtTri leftOutpt;
  };

  //------------------------------------------------------------------------------
  // ClipperTri 
  //------------------------------------------------------------------------------

  public class ClipperTri : Clipper
  {
    OutPt LastOp = null;
    Paths triangles = new Paths();

    //------------------------------------------------------------------------------
    //------------------------------------------------------------------------------

    private Int64 CrossProductVal(Point64 pt1, Point64 pt2, Point64 pt3, out Int64 val)
    {
      val = ((pt2.X - pt1.X) * (pt1.Y - pt3.Y) - (pt1.X - pt3.X) * (pt2.Y - pt1.Y));
      return val;
    }
    //------------------------------------------------------------------------------

    OutPt GetOutPt(Active e)
    {
      return (IsStartSide(e)) ? e.OutRec.Pts : e.OutRec.Pts.Next;
    }
    //------------------------------------------------------------------------------

    Active GetLeftAdjacentHotEdge(Active e)
    {
      Active result = e.PrevInAEL;
      while (result != null && !IsHotEdge(result)) result = result.PrevInAEL;
      return result;
    }
    //------------------------------------------------------------------------------

    Active GetRightAdjacentHotEdge(Active e)
    {
      Active result = e.NextInAEL;
      while (result != null && !IsHotEdge(result)) result = result.NextInAEL;
      return result;
    }
    //------------------------------------------------------------------------------

    private void DisposeOutPt(OutPt op)
    {
      if (op.Prev != null) op.Prev.Next = op.Next;
      if (op.Next != null) op.Next.Prev = op.Prev;
      OutPtTri opt = (OutPtTri)op;
      if (opt.rightOutrec != null) opt.rightOutrec.leftOutpt = null;
    }
    //------------------------------------------------------------------------------

    private void UpdateHelper(OutRec rightOutrec, OutPt leftOutpt)
    {
      OutPtTri leftOpt = (OutPtTri)leftOutpt;
      OutRecTri rightOrt = (OutRecTri)rightOutrec;
      if (leftOpt != null && leftOpt.rightOutrec != null)
        leftOpt.rightOutrec.leftOutpt = null;
      if (rightOrt.leftOutpt != null)
        rightOrt.leftOutpt.rightOutrec = null;
      rightOrt.leftOutpt = leftOpt;
      if (leftOpt != null) leftOpt.rightOutrec = rightOrt;
    }
    //------------------------------------------------------------------------------

    void Update(OutPt op, OutRec outrec)
    {
      OutPt op2 = op;
      do
      {
        OutPtTri opt = (OutPtTri)op2;
        if (opt.rightOutrec != null)
          UpdateHelper(opt.rightOutrec, null);
        opt.outrec = outrec;
        op2 = op2.Next;
      } while (op2 != op);
    }
    //------------------------------------------------------------------------------

    private int PointCount(OutPt op)
    {
      if (op == null) return 0;
      OutPt p = op;
      int cnt = 0;
      do
      {
        cnt++;
        p = p.Next;
      } while (p != op);
      return cnt;
    }
    //------------------------------------------------------------------------------

    private OutPtTri InsertPt(Point64 pt, OutPt afterOutPt)
    {
      OutPtTri result =(OutPtTri)CreateOutPt();
      result.Pt = pt;
      result.Prev = afterOutPt;
      result.Next = afterOutPt.Next;
      result.outrec = (afterOutPt as OutPtTri).outrec;
      result.rightOutrec = null;
      afterOutPt.Next.Prev = result;
      afterOutPt.Next = result;
      return result;
    }
    //------------------------------------------------------------------------------

    private void AddPolygon(Point64 pt1, Point64 pt2, Point64 pt3)
    {
      Path p = new Path();
      p.Capacity = 3;
      p.Add(pt3);
      p.Add(pt2);
      p.Add(pt1);
      triangles.Add(p);
    }
    //------------------------------------------------------------------------------

    private void Triangulate(OutRec outrec)
    {
      OutPt op = outrec.Pts;
      if (op.Next == op.Prev) return;
      OutPt end_op = op.Next;
      OutPtTri opt;
      for (;;)
      {
        OutPt op2 = op;
        Int64 cpval = 0;
        while (op.Prev != end_op)
        {
          if (CrossProductVal(op.Pt, op.Prev.Pt, op.Prev.Prev.Pt, out cpval) >= 0)
            break;
          if (op2 != op)
          {
            //Due to rounding, the clipping algorithm can occasionally produce
            //tiny self-intersections and these need removing ...
            if (CrossProductVal(op2.Pt, op.Pt, op.Prev.Prev.Pt, out cpval) > 0)
            {
              opt = (OutPtTri)op;
              if (opt.outrec != null) UpdateHelper(opt.outrec, op2);
              DisposeOutPt(op);
              op = op2;
              continue;
            }
          }
          op = op.Prev;
        }

        if (op.Prev == end_op) break;
        if (cpval != 0) AddPolygon(op.Pt, op.Prev.Pt, op.Prev.Prev.Pt);
        opt = (OutPtTri)op.Prev;
        if (opt.outrec != null) UpdateHelper(opt.outrec, op);
        DisposeOutPt(op.Prev);
        if (op != outrec.Pts) op = op.Next;
      }
    }
    //------------------------------------------------------------------------------

    private bool IsHotEdge(Active Edge)
    {
      return Edge.OutRec != null;
    }
    //------------------------------------------------------------------------------

    private bool IsStartSide(Active Edge)
    {
      return (Edge == Edge.OutRec.StartE);
    }
    //------------------------------------------------------------------------------

    protected override void AddLocalMinPoly(Active e1, Active e2, Point64 pt)
    {
      base.AddLocalMinPoly(e1, e2, pt);

      OutRec locMinOr = e1.OutRec;
      (locMinOr.Pts as OutPtTri).outrec = locMinOr;
      UpdateHelper(locMinOr, locMinOr.Pts);
      if (locMinOr.Flag == OutrecFlag.Outer) return;

      //do 'keyholing' ...
      Active e = GetRightAdjacentHotEdge(e1);
      if (e == e2) e = GetRightAdjacentHotEdge(e2);
      if (e == null) e = GetLeftAdjacentHotEdge(e1);
      OutPt botLft = (e.OutRec as OutRecTri).leftOutpt;
      OutPt botRt = GetOutPt(e);

      if (botLft == null || botRt.Pt.Y < botLft.Pt.Y) botLft = botRt;

      botRt = InsertPt(botLft.Pt, botLft.Prev);
      OutRec botOr = (botLft as OutPtTri).outrec;
      if (botOr.Pts == null) botOr = botOr.Owner;

      OutPt startOp = botOr.Pts;
      OutPt endOp = startOp.Next;

      locMinOr.Flag = OutrecFlag.Outer;
      locMinOr.Owner = null;
      OutPt locMinLft = locMinOr.Pts;
      OutPt locMinRt = InsertPt(locMinLft.Pt, locMinLft);

      //locMinOr will contain the polygon to the right of the join (ascending),
      //and botOr will contain the polygon to the left of the join (descending).

      //tail . botRt . locMinRt : locMinRt is joined by botRt tail
      locMinRt.Next = endOp;
      endOp.Prev = locMinRt;
      botRt.Next = locMinRt;
      locMinRt.Prev = botRt;
      locMinOr.Pts = locMinRt;

      //locMinLft . botLft . head : locMinLft joins behind botLft (left)
      startOp.Next = locMinLft;
      locMinLft.Prev = startOp;
      botLft.Prev = locMinLft;
      locMinLft.Next = botLft;
      (locMinLft as OutPtTri).outrec = botOr; //ie abreviated update()

      Update(locMinRt, locMinOr); //updates the outrec for each op

      //exchange endE's ...
      e = botOr.EndE;
      botOr.EndE = locMinOr.EndE;
      locMinOr.EndE = e;
      botOr.EndE.OutRec = botOr;
      locMinOr.EndE.OutRec = locMinOr;

      //update helper info  ...
      UpdateHelper(locMinOr, locMinRt);
      UpdateHelper(botOr, botOr.Pts);
      Triangulate(locMinOr);
      Triangulate(botOr);
    }
    //------------------------------------------------------------------------------

    protected override void AddLocalMaxPoly(Active e1, Active e2, Point64 Pt)
    {
      OutRec outrec = e1.OutRec;
      //very occasionally IsStartSide(e1) is wrong so ...
      bool is_outer = IsStartSide(e1) || (e1.OutRec == e2.OutRec);
      if (is_outer)
      {
        OutRecTri ort = (OutRecTri)(e1.OutRec);
        if (ort.leftOutpt != null) UpdateHelper(outrec, null);
        UpdateHelper(e2.OutRec, null);
      }

      base.AddLocalMaxPoly(e1, e2, Pt);

      if (outrec.Pts == null) outrec = outrec.Owner;

      if (is_outer)
      {
        OutPtTri ort = (OutPtTri)outrec.Pts;
        OutPtTri ort2 = (OutPtTri)outrec.Pts.Next;
        if (ort.rightOutrec != null)
          UpdateHelper(ort.rightOutrec, null);
        else if (ort2.rightOutrec != null)
          UpdateHelper(ort2.rightOutrec, null);
      }
      else
      {
        Active e = GetRightAdjacentHotEdge(e2);
        if (e != null) UpdateHelper(e.OutRec, LastOp);
        Update(outrec.Pts, outrec);
      }
      Triangulate(outrec);
    }
    //------------------------------------------------------------------------------

    protected override OutPt CreateOutPt()
    {
      //this is a virtual method as descendant classes may need
      //to produce descendant classes of OutPt ...
      return new OutPtTri();
    }
    //------------------------------------------------------------------------------

    protected override OutRec CreateOutRec()
    {
      //this is a virtual method as descendant classes may need
      //to produce descendant classes of OutRec ...
      return new OutRecTri();
    }
    //------------------------------------------------------------------------------

    protected override OutPt AddOutPt(Active e, Point64 pt)
    {
      OutPt result = base.AddOutPt(e, pt);
      OutPtTri opt = (OutPtTri)result;
      opt.outrec = e.OutRec;
      LastOp = result;
      Triangulate(e.OutRec);
      //Triangulate() above may assign Result.OutRecRt so ...
      if (IsStartSide(e) && opt.rightOutrec == null)
      {
        Active e2 = GetRightAdjacentHotEdge(e);
        if (e2 != null) UpdateHelper(e2.OutRec, result);
      }
      return result;
    }
    //------------------------------------------------------------------------------

    public override bool Execute(ClipType clipType, Paths triangles, FillRule ft = FillRule.EvenOdd)
    {
      try
      {
        if (triangles == null) return false;
        triangles.Clear();
        if (!ExecuteInternal(clipType, ft)) return false;
        triangles.Capacity = this.triangles.Count;
        foreach (Path p in this.triangles) triangles.Add(p);
        return true;
      }
      finally { CleanUp(); }
    }
    //------------------------------------------------------------------------------

    public override bool Execute(ClipType clipType, Paths Closed, Paths Open, FillRule ft = FillRule.EvenOdd)
    {
      return false; //unsupported
    }
    //------------------------------------------------------------------------------

    public override bool Execute(ClipType clipType, PolyTree polytree, Paths Open, FillRule ft = FillRule.EvenOdd)
    {
      return false; //unsupported
    }
    //------------------------------------------------------------------------------
  }//class

} //namespace
