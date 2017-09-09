/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  5 September 2017                                                *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************/

using System;
using System.Collections.Generic;
//using System.Text;          //for Int128.AsString() & StringBuilder
//using System.IO;            //debugging with streamReader & StreamWriter
//using System.Windows.Forms; //debugging to clipboard

namespace ClipperLib
{
  using cInt = Int64;

  using Path = List<IntPoint>;
  using Paths = List<List<IntPoint>>;

  public struct DoublePoint
  {
    public double X;
    public double Y;

    public DoublePoint(double x = 0, double y = 0)
    {
      this.X = x; this.Y = y;
    }
    public DoublePoint(DoublePoint dp)
    {
      this.X = dp.X; this.Y = dp.Y;
    }
    public DoublePoint(IntPoint ip)
    {
      this.X = ip.X; this.Y = ip.Y;
    }
  };

  public struct IntPoint
  {
    public cInt X;
    public cInt Y;
    public IntPoint(cInt X, cInt Y)
    {
        this.X = X; this.Y = Y;
    }
    public IntPoint(double x, double y)
    {
      this.X = (cInt)x; this.Y = (cInt)y;
    }

    public IntPoint(IntPoint pt)
    {
        this.X = pt.X; this.Y = pt.Y;
    }

    public static Boolean operator ==(IntPoint a, IntPoint b)
    {
      return a.X == b.X && a.Y == b.Y;
    }

    public static Boolean operator !=(IntPoint a, IntPoint b)
    {
      return a.X != b.X  || a.Y != b.Y; 
    }

    public override Boolean Equals(object obj)
    {
      if (obj == null) return false;
      if (obj is IntPoint)
      {
        IntPoint a = (IntPoint)obj;
        return (X == a.X) && (Y == a.Y);
      }
      else return false;
    }

    public override Int32 GetHashCode()
    {
      //simply prevents a compiler warning
      return base.GetHashCode();
    }

  }// } struct IntPoint

  public struct IntRect
  {
    public cInt left;
    public cInt top;
    public cInt right;
    public cInt bottom;

    public IntRect(cInt l, cInt t, cInt r, cInt b)
    {
      this.left = l; this.top = t;
      this.right = r; this.bottom = b;
    }
    public IntRect(IntRect ir)
    {
      this.left = ir.left; this.top = ir.top;
      this.right = ir.right; this.bottom = ir.bottom;
    }
  }

  public enum ClipType { ctIntersection, ctUnion, ctDifference, ctXor };
  public enum PolyType { ptSubject, ptClip };  
  //By far the most widely used winding rules for polygon filling are
  //EvenOdd & NonZero (GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32)
  //Others rules include Positive, Negative and ABS_GTR_EQ_TWO (only in OpenGL)
  //see http://glprogramming.com/red/chapter11.html
  public enum FillType { pftEvenOdd, pftNonZero, pftPositive, pftNegative };

  [Flags]
  internal enum VertexFlags { vfOpenStart = 1, vfOpenEnd = 2, vfLocMax = 4, vfLocMin = 8};

  internal class Vertex {
        internal IntPoint Pt;
        internal Vertex Next;
        internal Vertex Prev;
        internal VertexFlags Flags;
  }

  public class LocalMinima
  {
      internal Vertex Vertex;
      internal PolyType PolyType;
      internal Boolean IsOpen;
  };

  internal class Active {
    internal IntPoint Bot;
    internal IntPoint Curr; //current (updated for every new Scanline)
    internal IntPoint Top;
    internal double Dx;
    internal Int32 WindDx; //1 or -1 depending on winding direction
    internal Int32 WindCnt;
    internal Int32 WindCnt2; //winding count of the opposite polytype
    internal OutRec OutRec;
    internal Active NextInAEL;
    internal Active PrevInAEL;
    internal Active NextInSEL;
    internal Active PrevInSEL;
    internal Vertex VertTop;
    internal LocalMinima LocalMin;
  };

  public class ScanLine
  {
    internal cInt Y;
    internal ScanLine Next;
  };

  internal class OutPt
  {
    internal IntPoint Pt;
    internal OutPt Next;
    internal OutPt Prev;
  };

  [Flags]
  internal enum OutrecFlags { orOpen = 1, orOuter = 2, orHorz = 4, orHorzJoin = 8};

  //OutRec: contains a path in the clipping solution. Edges in the AEL will
  //carry a pointer to an OutRec when they are part of the clipping solution.
  internal class OutRec
  {
    internal Int32 IDx;
    internal OutRec Owner; 
    internal OutPt Pts;
    internal Active StartE;
    internal Active EndE;
    internal OutrecFlags Flags;
    internal PolyPath PolyPath;
  };

  public class IntersectNode
  {
      internal Active Edge1;
      internal Active Edge2;
      internal IntPoint Pt;
  };

  public class MyIntersectNodeSort : IComparer<IntersectNode>
  {
    public Int32 Compare(IntersectNode node1, IntersectNode node2)
    {
      return node2.Pt.Y.CompareTo(node1.Pt.Y); //descending soft
    }
  }

  public class MyLocalMinSort : IComparer<LocalMinima>
  {
    public Int32 Compare(LocalMinima lm1, LocalMinima lm2)
    {
      return lm2.Vertex.Pt.Y.CompareTo(lm1.Vertex.Pt.Y); //descending soft
    }
  }

  //------------------------------------------------------------------------------
  // Int128 struct (enables safe math on signed 64bit integers)
  // eg Int128 val1((Int64)9223372036854775807); //ie 2^63 -1
  //    Int128 val2((Int64)9223372036854775807);
  //    Int128 val3 = val1 * val2;
  //    val3.ToString => "85070591730234615847396907784232501249" (8.5e+37)
  //------------------------------------------------------------------------------

  internal struct Int128
  {
    private Int64 hi;
    private UInt64 lo;

    public Int128(Int64 _lo)
    {
      lo = (UInt64)_lo;
      if (_lo < 0) hi = -1;
      else hi = 0;
    }

    public Int128(Int64 _hi, UInt64 _lo)
    {
      lo = _lo;
      hi = _hi;
    }

    public Int128(Int128 val)
    {
      hi = val.hi;
      lo = val.lo;
    }

    public Boolean IsNegative()
    {
      return hi < 0;
    }

    public static Boolean operator ==(Int128 val1, Int128 val2)
    {
      if ((object)val1 == (object)val2) return true;
      else if ((object)val1 == null || (object)val2 == null) return false;
      return (val1.hi == val2.hi && val1.lo == val2.lo);
    }

    public static Boolean operator !=(Int128 val1, Int128 val2)
    {
      return !(val1 == val2);
    }

    public override Boolean Equals(System.Object obj)
    {
      if (obj == null || !(obj is Int128))
        return false;
      Int128 i128 = (Int128)obj;
      return (i128.hi == hi && i128.lo == lo);
    }

    public override Int32 GetHashCode()
    {
      return hi.GetHashCode() ^ lo.GetHashCode();
    }

    public static Int128 operator +(Int128 lhs, Int128 rhs)
    {
      lhs.hi += rhs.hi;
      lhs.lo += rhs.lo;
      if (lhs.lo < rhs.lo) lhs.hi++;
      return lhs;
    }

    public static Int128 operator -(Int128 val)
    {
      if (val.lo == 0)
        return new Int128(-val.hi, 0);
      else
        return new Int128(~val.hi, ~val.lo + 1);
    }

    public static explicit operator double(Int128 val)
    {
      const double shift64 = 18446744073709551616.0; //2^64
      if (val.hi < 0)
      {
        if (val.lo == 0)
          return (double)val.hi * shift64;
        else
          return -(double)(~val.lo + ~val.hi * shift64);
      }
      else
        return (double)(val.lo + val.hi * shift64);
    }

    //nb: Constructing two new Int128 objects every time we want to multiply longs  
    //is slow. So, although calling the Int128Mul method doesn't look as clean, the 
    //code runs significantly faster than if we'd used the * operator.

    public static Int128 Int128Mul(Int64 lhs, Int64 rhs)
    {
      Boolean negate = (lhs < 0) != (rhs < 0);
      if (lhs < 0) lhs = -lhs;
      if (rhs < 0) rhs = -rhs;
      UInt64 int1Hi = (UInt64)lhs >> 32;
      UInt64 int1Lo = (UInt64)lhs & 0xFFFFFFFF;
      UInt64 int2Hi = (UInt64)rhs >> 32;
      UInt64 int2Lo = (UInt64)rhs & 0xFFFFFFFF;

      //nb: see comments in clipper.pas
      UInt64 a = int1Hi * int2Hi;
      UInt64 b = int1Lo * int2Lo;
      UInt64 c = int1Hi * int2Lo + int1Lo * int2Hi;

      UInt64 lo;
      Int64 hi;
      hi = (Int64)(a + (c >> 32));

      unchecked { lo = (c << 32) + b; }
      if (lo < b) hi++;
      Int128 result = new Int128(hi, lo);
      return negate ? -result : result;
    }

  };

  //------------------------------------------------------------------------------
  // PolyTree & PolyNode classes
  //------------------------------------------------------------------------------

  public class PolyPath
  {
    internal PolyPath parent;
    internal List<PolyPath> childs = new List<PolyPath>();
    internal Path path = new Path();

    private Boolean IsHoleNode()
    {
      Boolean result = true;
      PolyPath node = parent;
      while (node != null)
      {
        result = !result;
        node = node.parent;
      }
      return result;
    }

    internal PolyPath AddChild(Path p)
    {
      PolyPath child = new PolyPath();
      child.parent = this;
      child.path = p;
      Childs.Add(child);
      return child;
    }

    public void Clear() { Childs.Clear(); }

    public Path Path { get { return path; } }

    public Int32 ChildCount { get { return childs.Count; } }

    public List<PolyPath> Childs { get { return childs; } }

    public PolyPath Parent { get { return parent; } }

    public Boolean IsHole { get { return IsHoleNode(); } }

  }

  public class PolyTree : PolyPath { };

  //------------------------------------------------------------------------------
  // Clipper2 
  //------------------------------------------------------------------------------

  public class Clipper2
  {
    internal const double horizontal = double.NegativeInfinity;
    internal const Int32 Unassigned = -1;

    internal ScanLine Scanline;
    internal Boolean HasOpenPaths;
    internal Boolean LocMinListSorted;
    internal List<List<Vertex>> VertexList = new List<List<Vertex>>();
    internal List<OutRec> OutRecList = new List<OutRec>();
    internal Int32 CurrentLocMinIdx;
    internal Active Actives;
    private Active SEL;
    private List<LocalMinima> LocMinimaList = new List<LocalMinima>();
    IComparer<LocalMinima> LocalMinimaComparer = new MyLocalMinSort();
    private List<IntersectNode> IntersectList = new List<IntersectNode>();
    IComparer<IntersectNode> IntersectNodeComparer = new MyIntersectNodeSort();
    private Boolean ExecuteLocked;
    private ClipType ClipType;
    private FillType FillType;

    private Boolean IsHotEdge(Active Edge)
    {
      return Edge.OutRec != null;
    }
    //------------------------------------------------------------------------------

    private Boolean IsStartSide(Active Edge)
    {
      return (Edge == Edge.OutRec.StartE);
    }
    //------------------------------------------------------------------------------

    internal static cInt Round(double value)
    {
      return value < 0 ? (cInt)(value - 0.5) : (cInt)(value + 0.5);
    }
    //------------------------------------------------------------------------------

    private static cInt TopX(Active edge, cInt currentY)
    {
      if (currentY == edge.Top.Y)
        return edge.Top.X;
      return edge.Bot.X + Round(edge.Dx * (currentY - edge.Bot.Y));
    }
    //------------------------------------------------------------------------------

    internal static Boolean IsHorizontal(Active e)
    {
      return e.Dx == double.NegativeInfinity;
    }
    //------------------------------------------------------------------------------

    internal static Boolean IsOpen(Active e)
    {
      return e.LocalMin.IsOpen;
    }
    //------------------------------------------------------------------------------

    public static double Area(Path poly)
    {
      Int32 cnt = poly.Count;
      if (cnt < 3) return 0;
      double a = 0;
      for (Int32 i = 0, j = cnt - 1; i < cnt; ++i)
      {
        a += ((double)poly[j].X + poly[i].X) * ((double)poly[j].Y - poly[i].Y);
        j = i;
      }
      return -a * 0.5;
    }
    //------------------------------------------------------------------------------

    internal double Area(OutPt op)
    {
      OutPt opFirst = op;
      if (op == null) return 0;
      double a = 0;
      do
      {
        a = a + (double)(op.Prev.Pt.X + op.Pt.X) * (double)(op.Prev.Pt.Y - op.Pt.Y);
        op = op.Next;
      } while (op != opFirst);
      return a * 0.5;
    }
    //------------------------------------------------------------------------------

    internal double Area(OutRec outRec)
    {
      return Area(outRec.Pts);
    }
    //------------------------------------------------------------------------------

    public static Boolean Orientation(Path poly)
    {
      return Area(poly) >= 0;
    }
    //------------------------------------------------------------------------------

    public static void ReversePaths(Paths polys)
    {
      foreach (var poly in polys) { poly.Reverse(); }
    }
    //------------------------------------------------------------------------------

    public static IntRect GetBounds(Paths paths)
    {
      Int32 i = 0, cnt = paths.Count;
      while (i < cnt && paths[i].Count == 0) i++;
      if (i == cnt) return new IntRect(0, 0, 0, 0);
      IntRect result = new IntRect();
      result.left = paths[i][0].X;
      result.right = result.left;
      result.top = paths[i][0].Y;
      result.bottom = result.top;
      for (; i < cnt; i++)
        for (Int32 j = 0; j < paths[i].Count; j++)
        {
          if (paths[i][j].X < result.left) result.left = paths[i][j].X;
          else if (paths[i][j].X > result.right) result.right = paths[i][j].X;
          if (paths[i][j].Y < result.top) result.top = paths[i][j].Y;
          else if (paths[i][j].Y > result.bottom) result.bottom = paths[i][j].Y;
        }
      return result;
    }
    //------------------------------------------------------------------------------

    public static Int32 PointInPolygon(IntPoint pt, Path path)
    {
      //returns 0 if false, +1 if true, -1 if pt ON polygon boundary
      //See "The Point in Polygon Problem for Arbitrary Polygons" by Hormann & Agathos
      //http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.88.5498&rep=rep1&type=pdf
      Int32 result = 0, cnt = path.Count;
      if (cnt < 3) return 0;
      IntPoint ip = path[0];
      for (Int32 i = 1; i <= cnt; ++i)
      {
        IntPoint ipNext = (i == cnt ? path[0] : path[i]);
        if (ipNext.Y == pt.Y)
        {
          if ((ipNext.X == pt.X) || (ip.Y == pt.Y &&
            ((ipNext.X > pt.X) == (ip.X < pt.X)))) return -1;
        }
        if ((ip.Y < pt.Y) != (ipNext.Y < pt.Y))
        {
          if (ip.X >= pt.X)
          {
            if (ipNext.X > pt.X) result = 1 - result;
            else
            {
              double d = (double)(ip.X - pt.X) * (ipNext.Y - pt.Y) -
                (double)(ipNext.X - pt.X) * (ip.Y - pt.Y);
              if (d == 0) return -1;
              else if ((d > 0) == (ipNext.Y > ip.Y)) result = 1 - result;
            }
          }
          else
          {
            if (ipNext.X > pt.X)
            {
              double d = (double)(ip.X - pt.X) * (ipNext.Y - pt.Y) -
                (double)(ipNext.X - pt.X) * (ip.Y - pt.Y);
              if (d == 0) return -1;
              else if ((d > 0) == (ipNext.Y > ip.Y)) result = 1 - result;
            }
          }
        }
        ip = ipNext;
      }
      return result;
    }
    //------------------------------------------------------------------------------

    internal cInt GetTopDeltaX(Active e1, Active e2)
    {
      if (e1.Top.Y > e2.Top.Y)
        return TopX(e2, e1.Top.Y) - e1.Top.X;
      else
        return e2.Top.X - TopX(e1, e2.Top.Y);
    }
    //------------------------------------------------------------------------------

    private bool E2InsertsBeforeE1(Active e1, Active e2, Boolean PreferLeft)
    {
      if (e2.Curr.X == e1.Curr.X)
      {
        return (PreferLeft ? GetTopDeltaX(e1, e2) <= 0 : GetTopDeltaX(e1, e2) < 0);
      }
      else return e2.Curr.X < e1.Curr.X;
    }
    //------------------------------------------------------------------------------

    private IntPoint GetIntersectPoint(Active edge1, Active edge2)
    {
      IntPoint ip = new IntPoint();
      double b1, b2;
      //nb: with very large coordinate values, it's possible for SlopesEqual() to 
      //return false but for the edge.Dx value be equal due to double precision rounding.
      if (edge1.Dx == edge2.Dx)
      {
        ip.Y = edge1.Curr.Y;
        ip.X = TopX(edge1, ip.Y);
        return ip;
      }

      if (edge1.Dx == 0)
      {
        ip.X = edge1.Bot.X;
        if (IsHorizontal(edge2))
        {
          ip.Y = edge2.Bot.Y;
        }
        else
        {
          b2 = edge2.Bot.Y - (edge2.Bot.X / edge2.Dx);
          ip.Y = Round(ip.X / edge2.Dx + b2);
        }
      }
      else if (edge2.Dx == 0)
      {
        ip.X = edge2.Bot.X;
        if (IsHorizontal(edge1))
        {
          ip.Y = edge1.Bot.Y;
        }
        else
        {
          b1 = edge1.Bot.Y - (edge1.Bot.X / edge1.Dx);
          ip.Y = Round(ip.X / edge1.Dx + b1);
        }
      }
      else
      {
        b1 = edge1.Bot.X - edge1.Bot.Y * edge1.Dx;
        b2 = edge2.Bot.X - edge2.Bot.Y * edge2.Dx;
        double q = (b2 - b1) / (edge1.Dx - edge2.Dx);
        ip.Y = Round(q);
        if (Math.Abs(edge1.Dx) < Math.Abs(edge2.Dx))
          ip.X = Round(edge1.Dx * q + b1);
        else
          ip.X = Round(edge2.Dx * q + b2);
      }
      return ip;
    }
    //------------------------------------------------------------------------------

    private void SetDx(Active e)
    {
      cInt dy = (e.Top.Y - e.Bot.Y);
      e.Dx = (dy == 0 ? double.NegativeInfinity : (double)(e.Top.X - e.Bot.X) / dy);
    }
    //---------------------------------------------------------------------------

    private Vertex NextVertex(Active e)
    {
      return (e.WindDx > 0 ? e.VertTop.Next : e.VertTop.Prev);
    }
    //------------------------------------------------------------------------------

    private Boolean IsMaxima(Active e)
    {
      return (VertexFlags.vfLocMax & e.VertTop.Flags) != 0;
    }
    //------------------------------------------------------------------------------

    internal Active GetMaximaPair(Active e)
    {
      Active e2;
      if (IsHorizontal(e))
      {
        //we can't be sure whether the MaximaPair is on the left or right, so ...
        e2 = e.PrevInAEL;
        while (e2 != null && e2.Curr.X >= e.Top.X)
        {
          if (e2.VertTop == e.VertTop) return e2;  //Found!
          e2 = e2.PrevInAEL;
        }
        e2 = e.NextInAEL;
        while (e2 != null && TopX(e2, e.Top.Y) <= e.Top.X)
        {
          if (e2.VertTop == e.VertTop) return e2;  //Found!
          e2 = e2.NextInAEL;
        }
      }
      else
      {
        e2 = e.NextInAEL;
        while (e2 != null)
        {
          if (e2.VertTop == e.VertTop) return e2; //Found!
          e2 = e2.NextInAEL;
        }
      }
      return null;
    }
    //------------------------------------------------------------------------------

    public void Clear()
    {
      LocMinimaList.Clear();
      CurrentLocMinIdx = 0;
      VertexList.Clear();
      HasOpenPaths = false;
    }
    //------------------------------------------------------------------------------

    public void CleanUp()
    {
      while (Actives != null) DeleteFromAEL(Actives);
      DisposeScanLineList();
      OutRecList.Clear();
    }
    //------------------------------------------------------------------------------

    private void Reset()
    {
      if (!LocMinListSorted)
      {
        LocMinimaList.Sort(LocalMinimaComparer);
        LocMinListSorted = true;
      }
      foreach (LocalMinima locMin in LocMinimaList)
        InsertScanline(locMin.Vertex.Pt.Y);
      CurrentLocMinIdx = 0;
      Actives = null;
      SEL = null;
    }
    //------------------------------------------------------------------------------

    private void InsertScanline(cInt Y)
    {
      //single-linked list: sorted descending, ignoring dups.
      if (Scanline == null)
      {
        Scanline = new ScanLine();
        Scanline.Next = null;
        Scanline.Y = Y;
      }
      else if (Y > Scanline.Y)
      {
        ScanLine newSb = new ScanLine();
        newSb.Y = Y;
        newSb.Next = Scanline;
        Scanline = newSb;
      }
      else
      {
        ScanLine sb2 = Scanline;
        while (sb2.Next != null && (Y <= sb2.Next.Y)) sb2 = sb2.Next;
        if (Y == sb2.Y) return; //ie ignores duplicates
        ScanLine newSb = new ScanLine();
        newSb.Y = Y;
        newSb.Next = sb2.Next;
        sb2.Next = newSb;
      }
    }
    //------------------------------------------------------------------------------

    internal Boolean PopScanline(out cInt Y)
    {
      if (Scanline == null)
      {
        Y = 0;
        return false;
      }
      Y = Scanline.Y;
      ScanLine tmp = Scanline.Next;
      Scanline = null;
      Scanline = tmp;
      return true;
    }
    //------------------------------------------------------------------------------

    private void DisposeScanLineList()
    {
      while (Scanline != null)
      {
        ScanLine tmp = Scanline.Next;
        Scanline = null;
        Scanline = tmp;
      }
    }
    //------------------------------------------------------------------------------

    private Boolean PopLocalMinima(cInt Y, out LocalMinima locMin)
    {
      locMin = null;
      if (CurrentLocMinIdx == LocMinimaList.Count) return false;
      locMin = LocMinimaList[CurrentLocMinIdx];
      if (locMin.Vertex.Pt.Y == Y)
      {
        CurrentLocMinIdx++;
        return true;
      }
      return false;
    }
    //------------------------------------------------------------------------------

    private void AddLocMin(Vertex vert, PolyType pt, Boolean isOpen)
    {
      //make sure the vertex is added only once ...
      if ((VertexFlags.vfLocMin & vert.Flags) != 0) return;
      vert.Flags |= VertexFlags.vfLocMin;
      LocalMinima lm = new LocalMinima();
      lm.Vertex = vert;
      lm.PolyType = pt;
      lm.IsOpen = isOpen;
      LocMinimaList.Add(lm);
    }
    //----------------------------------------------------------------------------

    private void AddPathToVertexList(Path p, PolyType pt, Boolean isOpen)
    {
      Int32 pathLen = p.Count;
      while (pathLen > 1 && p[pathLen - 1] == p[0]) pathLen--;
      if (pathLen < 2) return;

      Boolean P0IsMinima = false;
      Boolean P0IsMaxima = false;
      Boolean goingUp = false;
      Int32 i = 1;
      //find the first non-horizontal segment in the path ...
      while (i < pathLen && p[i].Y == p[0].Y) i++;
      if (i == pathLen) //it's a totally flat path
      {
        if (!isOpen) return;       //Ignore closed paths that have ZERO area.
      }
      else
      {
        goingUp = p[i].Y < p[0].Y; //because I'm using an inverted Y-axis display
        if (goingUp)
        {
          i = pathLen - 1;
          while (p[i].Y == p[0].Y) i--;
          P0IsMinima = p[i].Y < p[0].Y; //p[0].Y == a minima
        }
        else
        {
          i = pathLen - 1;
          while (p[i].Y == p[0].Y) i--;
          P0IsMaxima = p[i].Y > p[0].Y; //p[0].Y == a maxima
        }
      }

      List<Vertex> va = new List<Vertex>(pathLen);
      va[0].Pt = p[0];
      va[0].Flags = 0;

      if (isOpen)
      {
        va[0].Flags = VertexFlags.vfOpenStart;
        if (goingUp) AddLocMin(va[0], pt, isOpen);
        else va[0].Flags |= VertexFlags.vfLocMax;
      };

      //nb: polygon orientation is determined later (see InsertLocalMinimaIntoAEL).
      i = 0;
      for (Int32 j = 1; j < pathLen; j++)
      {
        if (p[j] == va[i].Pt) continue; //ie skips duplicates
        va[j].Pt = p[j];
        va[j].Flags = 0;
        va[i].Next = va[j];
        va[j].Prev = va[i];
        if (p[j].Y > p[i].Y && goingUp)
        {
          va[i].Flags |= VertexFlags.vfLocMax;
          goingUp = false;
        }
        else if (p[j].Y < p[i].Y && !goingUp)
        {
          goingUp = true;
          AddLocMin(va[i], pt, isOpen);
        }
        i = j;
      }
      //i: index of the last vertex in the path.
      va[i].Next = va[0];
      va[0].Prev = va[i];

      if (isOpen)
      {
        va[i].Flags |= VertexFlags.vfOpenEnd;
        if (goingUp) va[i].Flags |= VertexFlags.vfLocMax;
        else AddLocMin(va[i], pt, isOpen);
      }
      else
      {
        if (goingUp)
        {
          //going up so find local maxima ...
          Vertex v = va[i];
          while (v.Next.Pt.Y <= v.Pt.Y) v = v.Next;
          v.Flags |= VertexFlags.vfLocMax;
          if (P0IsMinima) AddLocMin(va[0], pt, isOpen); //ie just turned to going up
        }
        else
        {
          //going down so find local minima ...
          Vertex v = va[i];
          while (v.Next.Pt.Y >= v.Pt.Y) v = v.Next;
          AddLocMin(v, pt, isOpen);
          if (P0IsMaxima) va[0].Flags |= VertexFlags.vfLocMax;
        }
      }
      VertexList.Add(va);
    }
    //------------------------------------------------------------------------------

    public void AddPath(Path path, PolyType pt, Boolean isOpen)
    {
      if (isOpen)
      {
        if (pt == PolyType.ptClip)
          throw new ClipperException("AddPath: Only PolyType.Subject paths can be open.");
        HasOpenPaths = true;
      }
      AddPathToVertexList(path, pt, isOpen);
      LocMinListSorted = false;
    }
    //------------------------------------------------------------------------------

    public void AddPaths(Paths paths, PolyType pt, Boolean isOpen)
    {
      foreach (Path path in paths) AddPath(path, pt, isOpen);
    }
    //------------------------------------------------------------------------------

    private Boolean IsContributing(Active edge)
    {

      switch (this.FillType)
      {
        case FillType.pftEvenOdd:
          if (IsOpen(edge) && edge.WindCnt != 1) return false;
          break;
        case FillType.pftNonZero:
          if (Math.Abs(edge.WindCnt) != 1) return false;
          break;
        case FillType.pftPositive:
          if (edge.WindCnt != 1) return false;
          break;
        default: if (edge.WindCnt != -1) return false;
          break;
      }

      switch (this.ClipType)
      {
        case ClipType.ctIntersection:
          switch (FillType)
          {
            case FillType.pftEvenOdd:
            case FillType.pftNonZero:
              return (edge.WindCnt2 != 0);
            case FillType.pftPositive:
              return (edge.WindCnt2 > 0); 
            case FillType.pftNegative:
              return (edge.WindCnt2 < 0); 
          }
          break;
        case ClipType.ctUnion:
          switch (FillType)
          {
            case FillType.pftEvenOdd:
            case FillType.pftNonZero:
              return (edge.WindCnt2 == 0); 
            case FillType.pftPositive:
              return (edge.WindCnt2 <= 0); 
            case FillType.pftNegative:
              return (edge.WindCnt2 >= 0);
          }
          break;
        case ClipType.ctDifference:
          if (edge.LocalMin.PolyType == PolyType.ptSubject)
            switch (FillType)
            {
              case FillType.pftEvenOdd:
              case FillType.pftNonZero:
                return (edge.WindCnt2 == 0);
              case FillType.pftPositive:
                return (edge.WindCnt2 <= 0);
              case FillType.pftNegative:
                return (edge.WindCnt2 >= 0);
            }
          else
            switch (FillType)
            {
              case FillType.pftEvenOdd:
              case FillType.pftNonZero:
                return (edge.WindCnt2 != 0);
              case FillType.pftPositive:
                return (edge.WindCnt2 > 0); 
              case FillType.pftNegative:
                return (edge.WindCnt2 < 0); 
            }; break;
        case ClipType.ctXor:
          if (!IsOpen(edge)) return true; //XOr is always contributing unless open
          switch (FillType)
          {
            case FillType.pftEvenOdd:
            case FillType.pftNonZero:
              return (edge.WindCnt2 == 0);
            case FillType.pftPositive:
              return (edge.WindCnt2 <= 0);
            case FillType.pftNegative:
              return (edge.WindCnt2 >= 0);
          } break;
      }
      return false;
    }
    //------------------------------------------------------------------------------

    private void SetWindingCount(Active edge)
    {
      Active e = edge.PrevInAEL;
      //find the edge of the same polytype that immediately preceeds 'edge' in AEL
      while (e != null && ((e.LocalMin.PolyType != edge.LocalMin.PolyType) || IsOpen(e))) e = e.PrevInAEL;

      if (e == null)
      {
        if (IsOpen(edge))
          edge.WindCnt = (FillType == FillType.pftNegative ? -1 : 1);
        else
          edge.WindCnt = edge.WindDx;
        e = Actives; //ie get ready to calc WindCnt2
      }
      else if (IsOpen(edge) && ClipType != ClipType.ctUnion)
      {
        edge.WindCnt = 1;
        edge.WindCnt2 = e.WindCnt2;
        e = e.NextInAEL; //ie get ready to calc WindCnt2
      }
      else if (FillType == FillType.pftEvenOdd)
      {
        //even-odd filling ...
        if (IsOpen(edge))  //if edge is part of a line
        {
          //are we inside a subj polygon ...
          Boolean inside = true;
          Active e2 = e.PrevInAEL;
          while (e2 != null)
          {
            if (e2.LocalMin.PolyType == e.LocalMin.PolyType && !IsOpen(e2)) inside = !inside;
            e2 = e2.PrevInAEL;
          }
          edge.WindCnt = (inside ? 0 : 1);
        }
        else //else a polygon    
          edge.WindCnt = edge.WindDx;

        edge.WindCnt2 = e.WindCnt2;
        e = e.NextInAEL; //ie get ready to calc WindCnt2
      }
      else
      {
        //NonZero, Positive, or Negative filling ...
        if (e.WindCnt * e.WindDx < 0)
        {
          //prev edge is 'decreasing' WindCount (WC) toward zero
          //so we're outside the previous polygon ...
          if (Math.Abs(e.WindCnt) > 1)
          {
            //outside prev poly but still inside another.
            //when reversing direction of prev poly use the same WC
            if (e.WindDx * edge.WindDx < 0) edge.WindCnt = e.WindCnt;
            //otherwise continue to 'decrease' WC ...
            else edge.WindCnt = e.WindCnt + edge.WindDx;
          }
          else
            //now outside all polys of same polytype so set own WC ...
            edge.WindCnt = (IsOpen(edge) ? 1 : edge.WindDx);
        }
        else
        {
          //prev. edge is 'increasing' WindCount (WC) away from zero
          //so we're inside the previous polygon ...
          if (IsOpen(edge))
          {
            if (e.WindCnt < 0) e.WindCnt--; else e.WindCnt++;
          }
          //if wind direction is reversing then use same WC
          else if (e.WindDx * edge.WindDx < 0) edge.WindCnt = e.WindCnt;
          //otherwise add to WC ...
          else edge.WindCnt = e.WindCnt + edge.WindDx;
        };
        edge.WindCnt2 = e.WindCnt2;
        e = e.NextInAEL; //ie get ready to calc WindCnt2
      }

      //update WindCnt2 ...
      if (FillType == FillType.pftEvenOdd)
      {
        //even-odd filling ...
        while (e != edge)
        {
          if (e.LocalMin.PolyType != edge.LocalMin.PolyType && !IsOpen(e))
            edge.WindCnt2 = (edge.WindCnt2 == 0 ? 1 : 0);
          e = e.NextInAEL;
        }
      }
      else
      {
        //NonZero, Positive, or Negative filling ...
        while (e != edge)
        {
          if (e.LocalMin.PolyType != edge.LocalMin.PolyType && !IsOpen(e))
            edge.WindCnt2 += e.WindDx;
          e = e.NextInAEL;
        }
      }
    }
      //------------------------------------------------------------------------------

    private void InsertEdgeIntoAEL(Active edge, Active startEdge, Boolean preferLeft)
    {
      if (Actives == null) 
      {
        edge.PrevInAEL = null;
        edge.NextInAEL = null;
        Actives = edge;
      }
      else if (startEdge == null &&
        E2InsertsBeforeE1(Actives, edge, preferLeft))
      {
        edge.PrevInAEL = null;
        edge.NextInAEL = Actives;
        Actives.PrevInAEL = edge;
        Actives = edge;
      }
      else
      {
        if (startEdge == null) startEdge = Actives;
        while (startEdge.NextInAEL != null &&
          !E2InsertsBeforeE1(startEdge.NextInAEL, edge, preferLeft)) 
        {
          startEdge = startEdge.NextInAEL;
          preferLeft = false; //if there's one intervening then allow all
        }
        edge.NextInAEL = startEdge.NextInAEL;
        if (startEdge.NextInAEL != null) 
          startEdge.NextInAEL.PrevInAEL = edge;
        edge.PrevInAEL = startEdge;
        startEdge.NextInAEL = edge;
      }
    }
    //----------------------------------------------------------------------

    private void InsertLocalMinimaIntoAEL(cInt BotY)
    //E: PActive;
    //LeftB, RightB, tmp: PActive;
    //;
    //contributing: Boolean;
    {
      LocalMinima locMin;
      Active leftB, rightB;
      //Add any local minima at BotY ...
      while (PopLocalMinima(BotY, out locMin))
      {
        if ((locMin.Vertex.Flags & VertexFlags.vfOpenStart) > 0)
        {
          leftB = null;
        }
        else
        {
          leftB = new Active();
          leftB.Bot = locMin.Vertex.Pt;
          leftB.Curr = leftB.Bot;
          leftB.VertTop = locMin.Vertex.Prev; //ie descending
          leftB.Top = leftB.VertTop.Pt;
          leftB.WindDx = -1;
          leftB.LocalMin = locMin;
          SetDx(leftB);
        }

        if ((locMin.Vertex.Flags & VertexFlags.vfOpenEnd) > 0)
        {
          rightB = null;
        }
        else
        {
          rightB = new Active();
          rightB.Bot = locMin.Vertex.Pt;
          rightB.Curr = rightB.Bot;
          rightB.VertTop = locMin.Vertex.Next; //ie ascending
          rightB.Top = rightB.VertTop.Pt;
          rightB.WindDx = 1;
          rightB.LocalMin = locMin;
          SetDx(rightB);
        }

        //Currently LeftB is just the descending bound and RightB is the ascending.
        //Now if the LeftB isn't on the left of RightB then we need swap them.
        if (leftB != null && rightB != null) 
        {
          if ((IsHorizontal(leftB) && leftB.Top.X > leftB.Bot.X) ||
            (!IsHorizontal(leftB) && leftB.Dx < rightB.Dx)) 
          {
            Active tmp = leftB;
            leftB = rightB;
            rightB = tmp;
           }
        }
        else if (leftB == null) 
        {
          leftB = rightB;
          rightB = null;
        }

        InsertEdgeIntoAEL(leftB, null, false);      //insert left edge
        SetWindingCount(leftB);
        Boolean contributing = IsContributing(leftB);

        if (rightB != null) 
        {
          rightB.WindCnt = leftB.WindCnt;
            rightB.WindCnt2 = leftB.WindCnt2;
          InsertEdgeIntoAEL(rightB, leftB, false); //insert right edge
          if (contributing) 
            AddLocalMinPoly(leftB, rightB, leftB.Bot);

            if (IsHorizontal(rightB))
              PushHorz(rightB);
            else
              InsertScanline(rightB.Top.Y);
        }
        else if (IsContributing(leftB))
        {
          //ie open path that's not at a local minima
          StartOpenPath(leftB, leftB.Bot);
          AddOutPt(leftB, leftB.Bot);
        }

        if (IsHorizontal(leftB))
          PushHorz(leftB); else
          InsertScanline(leftB.Top.Y);

        if (rightB != null && leftB.NextInAEL != rightB) 
        {
          //intersect edges that are between left and right bounds ...
          Active e = leftB.NextInAEL;
          while (e != rightB)
          {
            //nb: For calculating winding counts etc, IntersectEdges() assumes
            //that param1 will be to the right of param2 ABOVE the intersection ...
            IntersectEdges(rightB, e, rightB.Bot);
            e = e.NextInAEL;
          }
        }
      }
    }
    //------------------------------------------------------------------------------

    private void Clockwise(OutRec outRec, Active e1, Active e2)
    {
      outRec.StartE = e1;
      outRec.EndE = e2;
    }
    //------------------------------------------------------------------------------

    private void CounterClockwise(OutRec outRec, Active e1, Active e2)
    {
      outRec.StartE = e2;
      outRec.EndE = e1;
    }
    //------------------------------------------------------------------------------

    private OutRec SetOwner(Active e)
    {
      if (IsHorizontal(e)  && e.Top.X < e.Bot.X)
      {
        e = e.NextInAEL;
        while (e != null && (!IsHotEdge(e) || IsOpen(e))) 
          e = e.NextInAEL;
        if (e == null) return null;
        else if (((e.OutRec.Flags & OutrecFlags.orOuter) != 0) == (e.OutRec.StartE == e))
          return e.OutRec.Owner; else return e.OutRec;
      }
      else
      {
        e = e.PrevInAEL;
        while (e != null && (!IsHotEdge(e) || IsOpen(e)))
          e = e.PrevInAEL;
        if (e == null) return null;
        else if (((e.OutRec.Flags & OutrecFlags.orOuter) != 0) == (e.OutRec.EndE == e))
          return e.OutRec.Owner; else return e.OutRec;
      }
    }
    //------------------------------------------------------------------------------

    private void AddLocalMinPoly(Active e1, Active e2, IntPoint pt)
    {
      OutRec outRec = new OutRec();
      OutRecList.Add(outRec);
      outRec.Owner = SetOwner(e1);
      if (outRec.Owner != null && (outRec.Owner.Flags & OutrecFlags.orOuter) != 0)
        outRec.Flags = 0; else
        outRec.Flags |= OutrecFlags.orOuter;
      if (IsOpen(e1)) outRec.Flags |= OutrecFlags.orOpen;
      outRec.PolyPath = null;

      //now set orientation ...
      if (IsHorizontal(e1))
      {
        if (IsHorizontal(e2))
        {
          if (((outRec.Flags & OutrecFlags.orOuter) != 0) == (e1.Bot.X > e2.Bot.X))
            Clockwise(outRec, e1, e2); else CounterClockwise(outRec, e1, e2);
        }
        else if (((outRec.Flags & OutrecFlags.orOuter) != 0) == (e1.Top.X < e1.Bot.X))
          Clockwise(outRec, e1, e2); else CounterClockwise(outRec, e1, e2);
      }
      else if (IsHorizontal(e2))
      {
        if (((outRec.Flags & OutrecFlags.orOuter) != 0) == (e2.Top.X > e2.Bot.X))
          Clockwise(outRec, e1, e2); else CounterClockwise(outRec, e1, e2);
      }
      else if (((outRec.Flags & OutrecFlags.orOuter) != 0) == (e1.Dx >= e2.Dx))
        Clockwise(outRec, e1, e2); else CounterClockwise(outRec, e1, e2);

      e1.OutRec = outRec;
      e2.OutRec = outRec;

      OutPt op = new OutPt();
      op.Pt = pt;
      op.Next = op;
      op.Prev = op;
      outRec.Pts = op;
    }
    //------------------------------------------------------------------------------

    private void EndOutRec(OutRec outRec)
    {
      outRec.StartE.OutRec = null;
      if (outRec.EndE != null) outRec.EndE.OutRec = null;
      outRec.StartE = null;
      outRec.EndE = null;
    }
    //------------------------------------------------------------------------------

    private void AddLocalMaxPoly(Active e1, Active e2, IntPoint Pt)
    {
      AddOutPt(e1, Pt);
      if (e1.OutRec == e2.OutRec) EndOutRec(e1.OutRec);
      //and to preserve the winding orientation of Outrec ...
      else if (e1.OutRec.IDx < e2.OutRec.IDx)
        JoinOutrecPaths(e1, e2); else
        JoinOutrecPaths(e2, e1);
    }
    //------------------------------------------------------------------------------

    private void ReversePolyPtLinks(OutPt op)
    {
      if (op.Next == op.Prev) return;
      OutPt pp1 = op, pp2;
      do {
        pp2 = pp1.Next;
        pp1.Next = pp1.Prev;
        pp1.Prev = pp2;
        pp1 = pp2;
      }
      while (pp1 != op);
    }
    //------------------------------------------------------------------------------

    private void JoinOutrecPaths(Active e1, Active e2)
    {
      OutPt P1_st, P1_end, P2_st, P2_end;

      //join E2 outrec path onto E1 outrec path and then delete E2 outrec path
      //pointers. (nb: Only very rarely do the joining ends share the same coords.)
      P1_st = e1.OutRec.Pts;
      P2_st = e2.OutRec.Pts;
      P1_end = P1_st.Prev;
      P2_end = P2_st.Prev;
      if (IsStartSide(e1))
      {
        if (IsStartSide(e2))
        {
          //start-start join
          ReversePolyPtLinks(P2_st);
          P2_st.Next = P1_st;
          P1_st.Prev = P2_st;
          P1_end.Next = P2_end; //P2 now reversed
          P2_end.Prev = P1_end;
          e1.OutRec.Pts = P2_end;
          e1.OutRec.StartE = e2.OutRec.EndE;
        } else
        {
          //}-start join
          P2_end.Next = P1_st;
          P1_st.Prev = P2_end;
          P2_st.Prev = P1_end;
          P1_end.Next = P2_st;
          e1.OutRec.Pts = P2_st;
          e1.OutRec.StartE = e2.OutRec.StartE;
        }
        if (e1.OutRec.StartE != null) //ie closed path
          e1.OutRec.StartE.OutRec = e1.OutRec;
      }
      else
      {
        if (IsStartSide(e2))
        {
          //}-start join (see JoinOutrec3.png)
          P1_end.Next = P2_st;
          P2_st.Prev = P1_end;
          P1_st.Prev = P2_end;
          P2_end.Next = P1_st;
          e1.OutRec.EndE = e2.OutRec.EndE;
        }
        else
        {
          //}-} join (see JoinOutrec4.png)
          ReversePolyPtLinks(P2_st);
          P1_end.Next = P2_end; //P2 now reversed
          P2_end.Prev = P1_end;
          P2_st.Next = P1_st;
          P1_st.Prev = P2_st;
          e1.OutRec.EndE = e2.OutRec.StartE;
        }
        if (e1.OutRec.EndE != null) //ie closed path
          e1.OutRec.EndE.OutRec = e1.OutRec;
      }

      if (e1.OutRec.Owner == e2.OutRec)
        throw new ClipperException("Clipping error in JoinOuterPaths.");

      //after joining, the E2.OutRec contains not vertices ...
      e2.OutRec.StartE = null;
      e2.OutRec.EndE = null;
      e2.OutRec.Pts = null;
      e2.OutRec.Owner = e1.OutRec; //this may be redundant

      //and e1 and e2 are maxima and are about to be dropped from the Actives list.
      e1.OutRec = null;
      e2.OutRec = null;
    }
    //------------------------------------------------------------------------------

    private void PushHorz(Active e)
    {
      e.NextInSEL = (SEL != null ? SEL : null);
      SEL = e;
    }
    //------------------------------------------------------------------------------

    private Boolean PopHorz(out Active e)
    {
      e = SEL;
      if (e == null) return false;
      SEL = SEL.NextInSEL;
      return true;
    }
      //------------------------------------------------------------------------------

    private void StartOpenPath(Active e, IntPoint pt)
    {
      OutRec outRec = new OutRec();
      outRec.IDx = OutRecList.Count;
      OutRecList.Add(outRec);
      outRec.Flags = OutrecFlags.orOpen;
      e.OutRec = outRec;

      OutPt op = new OutPt();
      op.Pt = pt;
      op.Next = op;
      op.Prev = op;
      outRec.Pts = op;
    }
    //------------------------------------------------------------------------------

    private void TerminateHotOpen(Active e)
    {
      if (e.OutRec.StartE == e)
        e.OutRec.StartE = null; else
        e.OutRec.EndE = null;
      e.OutRec = null;
    }
    //------------------------------------------------------------------------------

    private void SwapOutrecs(Active e1, Active e2)
    {
      OutRec or1 = e1.OutRec;
      OutRec or2 = e2.OutRec;
      if (or1 == or2)
      {
        Active e = or1.StartE;
        or1.StartE = or1.EndE;
        or1.EndE = e;
        return;
      }
      if (or1 != null)
      {
        if (e1 == or1.StartE)
          or1.StartE = e2; else
          or1.EndE = e2;
      }
      if (or2 != null)
      {
        if (e2 == or2.StartE)
          or2.StartE = e1; else
          or2.EndE = e1;
      }
      e1.OutRec = or2;
      e2.OutRec = or1;
    }
      //------------------------------------------------------------------------------

      private void AddOutPt(Active e, IntPoint pt)
      {

        //Outrec.Pts: a circular double-linked-list of POutPt.
        Boolean toStart = IsStartSide(e);
        OutPt opStart = e.OutRec.Pts;
        OutPt opEnd = opStart.Prev;
        if (toStart)
        {
          if (pt == opStart.Pt) return;
        }
        else if (pt == opEnd.Pt) return;

        OutPt opNew = new OutPt();
        opNew.Pt = pt;
        opNew.Next = opStart;
        opNew.Prev = opEnd;
        opEnd.Next = opNew;
        opStart.Prev = opNew;
        if (toStart) e.OutRec.Pts = opNew;
      }
      //------------------------------------------------------------------------------

      private void UpdateEdgeIntoAEL(ref Active e)
      {
        e.Bot = e.Top;
        e.VertTop = NextVertex(e);
        e.Top = e.VertTop.Pt;
        e.Curr = e.Bot;
        SetDx(e);
        if (!IsHorizontal(e)) InsertScanline(e.Top.Y);
      }
      //------------------------------------------------------------------------------

      private void IntersectEdges(Active e1, Active e2, IntPoint pt)
      {
        //e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
        //e2 in AEL except when e1 is being inserted at the intersection point ...

        Boolean e1Contributing = IsHotEdge(e1);
        Boolean e2Contributing = IsHotEdge(e2);

        e1.Curr = pt;
        e2.Curr = pt;

        //if either edge is on an OPEN path ...
        if (HasOpenPaths && (IsOpen(e1) || IsOpen(e2)))
        {
          //ignore subject-subject open path intersections,
          //unless they're the same OutRec and hence need joining ...
          if (IsOpen(e1) && IsOpen(e2))
          {
            if (e1Contributing && (e1.OutRec == e2.OutRec))
              AddLocalMaxPoly(e1, e2, pt);
            return;
          }
          //if intersecting a subj line with a subj poly ...
          else if (e1.LocalMin.PolyType == e2.LocalMin.PolyType &&
            e1.WindDx != e2.WindDx && ClipType == ClipType.ctUnion)
          {
            if (IsOpen(e1))
            {
              if (e2Contributing)
              {
                if (!e1Contributing) StartOpenPath(e1, pt);
                AddOutPt(e1, pt);
                if (e1Contributing) TerminateHotOpen(e1);
              }
            }
            else
            {
              if (e1Contributing)
              {
                if (!e2Contributing) StartOpenPath(e2, pt);
                AddOutPt(e2, pt);
                if (e2Contributing) TerminateHotOpen(e2);
              }
            }
          }
          else if (e1.LocalMin.PolyType != e2.LocalMin.PolyType)
          {
            if (IsOpen(e1) && Math.Abs(e2.WindDx) == 1 &&
              (ClipType != ClipType.ctUnion || e2.WindCnt2 == 0))
            {
              if (!e1Contributing) StartOpenPath(e1, pt);
              AddOutPt(e1, pt);
              if (e1Contributing) TerminateHotOpen(e1);
            }
            else if (IsOpen(e2) && Math.Abs(e1.WindCnt) == 1 &&
                (ClipType != ClipType.ctUnion || e1.WindCnt2 == 0))
            {
              if (!e2Contributing) StartOpenPath(e2, pt);
              AddOutPt(e2, pt);
              if (e2Contributing) TerminateHotOpen(e2);
            }
          }
          return;
        }

        //update winding counts...
        //assumes that e1 will be to the Right of e2 ABOVE the intersection
        Int32 oldE1WindCnt, oldE2WindCnt;
        if (e1.LocalMin.PolyType == e2.LocalMin.PolyType)
        {
          if (FillType == FillType.pftEvenOdd)
          {
            oldE1WindCnt = e1.WindCnt;
            e1.WindCnt = e2.WindCnt;
            e2.WindCnt = oldE1WindCnt;
          }
          else
          {
            if (e1.WindCnt + e2.WindDx == 0) e1.WindCnt = -e1.WindCnt;
            else e1.WindCnt += e2.WindDx;
            if (e2.WindCnt - e1.WindDx == 0) e2.WindCnt = -e2.WindCnt;
            else e2.WindCnt -= e1.WindDx;
          }
        }
        else
        {
          if (FillType != FillType.pftEvenOdd) e1.WindCnt2 += e2.WindDx;
          else e1.WindCnt2 = (e1.WindCnt2 == 0) ? 1 : 0;
          if (FillType != FillType.pftEvenOdd) e2.WindCnt2 -= e1.WindDx;
          else e2.WindCnt2 = (e2.WindCnt2 == 0) ? 1 : 0;
        }

        switch (FillType)
        {
          case FillType.pftPositive:
            oldE1WindCnt = e1.WindCnt;
            oldE2WindCnt = e2.WindCnt;
            break;
          case FillType.pftNegative:
            oldE1WindCnt = -e1.WindCnt;
            oldE2WindCnt = -e2.WindCnt;
            break;
          default:
            oldE1WindCnt = Math.Abs(e1.WindCnt);
            oldE2WindCnt = Math.Abs(e2.WindCnt);
            break;
        }

        if (e1Contributing && e2Contributing)
        {
          if ((oldE1WindCnt != 0 && oldE1WindCnt != 1) || (oldE2WindCnt != 0 && oldE2WindCnt != 1) ||
            (e1.LocalMin.PolyType != e2.LocalMin.PolyType && ClipType != ClipType.ctXor))
          {
            AddLocalMaxPoly(e1, e2, pt);
          }
          else if (e1.OutRec == e2.OutRec) //optional
          {
            AddLocalMaxPoly(e1, e2, pt);
            AddLocalMinPoly(e1, e2, pt);
          }
          else
          {
            AddOutPt(e1, pt);
            AddOutPt(e2, pt);
            SwapOutrecs(e1, e2);
          }
        }
        else if (e1Contributing)
        {
          if (oldE2WindCnt == 0 || oldE2WindCnt == 1)
          {
            AddOutPt(e1, pt);
            SwapOutrecs(e1, e2);
          }
        }
        else if (e2Contributing)
        {
          if (oldE1WindCnt == 0 || oldE1WindCnt == 1)
          {
            AddOutPt(e2, pt);
            SwapOutrecs(e1, e2);
          }
        }
        else if ((oldE1WindCnt == 0 || oldE1WindCnt == 1) && (oldE2WindCnt == 0 || oldE2WindCnt == 1))
        {
          //neither edge is currently contributing ...
          cInt e1Wc2, e2Wc2;
          switch (FillType)
          {
            case FillType.pftPositive:
              e1Wc2 = e1.WindCnt2;
              e2Wc2 = e2.WindCnt2;
              break;
            case FillType.pftNegative:
              e1Wc2 = -e1.WindCnt2;
              e2Wc2 = -e2.WindCnt2;
              break;
            default:
              e1Wc2 = Math.Abs(e1.WindCnt2);
              e2Wc2 = Math.Abs(e2.WindCnt2);
              break;
          }

          if (e1.LocalMin.PolyType != e2.LocalMin.PolyType)
          {
            AddLocalMinPoly(e1, e2, pt);
          }
          else if (oldE1WindCnt == 1 && oldE2WindCnt == 1)
            switch (ClipType)
            {
              case ClipType.ctIntersection:
                if (e1Wc2 > 0 && e2Wc2 > 0)
                  AddLocalMinPoly(e1, e2, pt);
                break;
              case ClipType.ctUnion:
                if (e1Wc2 <= 0 && e2Wc2 <= 0)
                  AddLocalMinPoly(e1, e2, pt);
                break;
              case ClipType.ctDifference:
                if (((e1.LocalMin.PolyType == PolyType.ptClip) && (e1Wc2 > 0) && (e2Wc2 > 0)) ||
                    ((e1.LocalMin.PolyType == PolyType.ptSubject) && (e1Wc2 <= 0) && (e2Wc2 <= 0)))
                  AddLocalMinPoly(e1, e2, pt);
                break;
              case ClipType.ctXor:
                AddLocalMinPoly(e1, e2, pt);
                break;
            }
        }
      }
      //------------------------------------------------------------------------------

      private void DeleteFromAEL(Active e)
      {
        Active AelPrev = e.PrevInAEL;
        Active AelNext = e.NextInAEL;
        if (AelPrev == null && AelNext == null && (e != Actives))
          return; //already deleted
        if (AelPrev != null) AelPrev.NextInAEL = AelNext;
        else Actives = AelNext;
        if (AelNext != null)
          AelNext.PrevInAEL = AelPrev;
        e.NextInAEL = null;
        e.PrevInAEL = null;
      }
      //------------------------------------------------------------------------------

      private void CopyAELToSEL()
      {
        Active e = Actives;
        SEL = e;
        while (e != null)
        {
          e.PrevInSEL = e.PrevInAEL;
          e.NextInSEL = e.NextInAEL;
          e = e.NextInAEL;
        }
      }
      //------------------------------------------------------------------------------

      private Boolean ExecuteInternal(ClipType ct, FillType ft)
      {
        if (ExecuteLocked) return false;
        try
        {
          ExecuteLocked = true;
          FillType = ft;
          ClipType = ct;
          Reset();
          cInt Y;
          Active e;
          if (!PopScanline(out Y)) return false;

          while (true) /////////////////////////////////////////////
          {
            InsertLocalMinimaIntoAEL(Y);
            while (PopHorz(out e)) ProcessHorizontal(e);
            if (!PopScanline(out Y)) break; //Y == top of scanbeam
            ProcessIntersections(Y);          //process scanbeam intersections
            DoTopOfScanbeam(Y); //leaves pending horizontals for next loop iteration
          } ////////////////////////////////////////////////////////
        }
        finally
        { ExecuteLocked = false; }
        return true;
      }
      //------------------------------------------------------------------------------

        public Boolean Execute(ClipType clipType, Paths Closed, FillType ft = FillType.pftEvenOdd)
        {
        try
        {
          if (Closed == null) return false;
          Closed.Clear();
          if (!ExecuteInternal(clipType, ft)) return false;
          BuildResult(Closed, null);
          return true;
        }
        finally { CleanUp(); }
      }
      //------------------------------------------------------------------------------

      public Boolean Execute(ClipType clipType, Paths Closed, Paths Open, FillType ft = FillType.pftEvenOdd)
        {
          try
          {
            if (Closed == null) return false;
            Closed.Clear();
            if (Open != null) Open.Clear();
            if (!ExecuteInternal(clipType, ft)) return false;
            BuildResult(Closed, Open);
            return true;
          }
          finally { CleanUp(); }
      }
      //------------------------------------------------------------------------------

      public Boolean Execute(ClipType clipType, PolyTree polytree, Paths Open, FillType ft = FillType.pftEvenOdd)
        {
        try
        {
          if (polytree == null) return false;
          polytree.Clear();
          if (Open != null) Open.Clear();
          if (!ExecuteInternal(clipType, ft)) return false;
          BuildResult2(polytree, Open);
          return true;
        }
        finally { CleanUp(); }
      }
      //------------------------------------------------------------------------------

      private void ProcessIntersections(cInt topY)
      {
        try
        {
          BuildIntersectList(topY);
          if (IntersectList.Count == 0) return;
          FixupIntersectionOrder();
          ProcessIntersectList();
        }
        finally
        {
          IntersectList.Clear(); //clean up if there's been an error
          SEL = null;
        }
      }
      //------------------------------------------------------------------------------

      private void BuildIntersectList(cInt TopY)
      //var
      //  E, eNext: PActive;
      //  Pt: TIntPoint;
      //  IsModified: Boolean;
      //  NewNode: PIntersectNode;
      {
        if (Actives == null) return;

        //copy AEL to SEL while also adjusting Curr.X ...
        SEL = Actives;
        Active e = Actives;
        while (e != null)
        {
          e.PrevInSEL = e.PrevInAEL;
          e.NextInSEL = e.NextInAEL;
          e.Curr.X = TopX(e, TopY);
          e = e.NextInAEL;
        }

        Boolean IsModified;
        IntPoint pt;
        //bubblesort (because adjacent swaps are required) ...
        do {
          IsModified = false;
          e = SEL;
          while (e.NextInSEL != null)
          {
            Active eNext = e.NextInSEL;
            if (e.Curr.X > eNext.Curr.X)
            {
              //An intersection is occuring somewhere within the scanbeam ...
              pt = GetIntersectPoint(e, eNext);

              //Rounding errors can occasionally place the calculated intersection
              //point either below or above the scanbeam, so check and correct ...
              if (pt.Y > e.Curr.Y)
              {
                pt.Y = e.Curr.Y;      //E.Curr.Y is still the bottom of scanbeam
                //use the more vertical of the 2 edges to derive pt.X ...
                if (Math.Abs(e.Dx) < Math.Abs(eNext.Dx))
                  pt.X = TopX(e, pt.Y); else
                  pt.X = TopX(eNext, pt.Y);
              }
              else if (pt.Y < TopY)
              {
                pt.Y = TopY;          //TopY = top of scanbeam
                if (e.Top.Y == TopY)
                  pt.X = e.Top.X;
                else if (eNext.Top.Y == TopY)
                  pt.X = eNext.Top.X;
                else if (Math.Abs(e.Dx) < Math.Abs(eNext.Dx))
                  pt.X = e.Curr.X;
                else
                  pt.X = eNext.Curr.X;
              }

              IntersectNode NewNode = new IntersectNode();
              NewNode.Edge1 = e;
              NewNode.Edge2 = eNext;
              NewNode.Pt = pt;
              IntersectList.Add(NewNode);
              SwapPositionsInSEL(e, eNext);
              IsModified = true;
            }
            else
              e = eNext;
          }

          if (e.PrevInSEL == null) break;
          e.PrevInSEL.NextInSEL = null; 
        }
        while (IsModified);
      }
      //------------------------------------------------------------------------------

      private void ProcessIntersectList()
      {
        foreach (IntersectNode iNode in IntersectList)
        {
          IntersectEdges(iNode.Edge1, iNode.Edge2, iNode.Pt);
          SwapPositionsInAEL(iNode.Edge1, iNode.Edge2);
        }
        IntersectList.Clear();
      }
      //------------------------------------------------------------------------------

      private Boolean EdgesAdjacent(IntersectNode inode)
      {
        return (inode.Edge1.NextInSEL == inode.Edge2) ||
          (inode.Edge1.PrevInSEL == inode.Edge2);
      }
      //------------------------------------------------------------------------------

      private static Int32 IntersectNodeSort(IntersectNode node1, IntersectNode node2)
      {
        //the following typecast should be safe because the differences in Pt.Y will
        //be limited to the height of the Scanline ...
        return (Int32)(node2.Pt.Y - node1.Pt.Y);
      }
      //------------------------------------------------------------------------------

      private void FixupIntersectionOrder()
      {
        //pre-condition: intersections are sorted bottom-most first.
        //Now it's crucial that intersections are made only between adjacent edges,
        //so to ensure this the order of intersections may need Bubble sorting ...
        Int32 cnt = IntersectList.Count;
        if (cnt < 3) return; //any edges must be adjacent :)
        IntersectList.Sort(IntersectNodeComparer);
        CopyAELToSEL();
        for (Int32 i = 0; i < cnt; i++)
        {
          if (!EdgesAdjacent(IntersectList[i]))
          {
            Int32 j = i + 1;
            while (j < cnt && !EdgesAdjacent(IntersectList[j])) j++;
            IntersectNode tmp = IntersectList[i];
            IntersectList[i] = IntersectList[j];
            IntersectList[j] = tmp;
          }
          SwapPositionsInSEL(IntersectList[i].Edge1, IntersectList[i].Edge2);
        }
      }
      //------------------------------------------------------------------------------

      internal void SwapPositionsInAEL(Active e1, Active e2)
      {
        Active next, prev;
        if (e1.NextInAEL == e2)
        {
          next = e2.NextInAEL;
          if (next != null) next.PrevInAEL = e1;
          prev = e1.PrevInAEL;
          if (prev != null) prev.NextInAEL = e2;
          e2.PrevInAEL = prev;
          e2.NextInAEL = e1;
          e1.PrevInAEL = e2;
          e1.NextInAEL = next;
          if (e2.PrevInAEL == null) Actives = e2;
        }
        else if (e2.NextInAEL == e1)
        {
          next = e1.NextInAEL;
          if (next != null) next.PrevInAEL = e2;
          prev = e2.PrevInAEL;
          if (prev != null) prev.NextInAEL = e1;
          e1.PrevInAEL = prev;
          e1.NextInAEL = e2;
          e2.PrevInAEL = e1;
          e2.NextInAEL = next;
          if (e1.PrevInAEL == null) Actives = e1;
        }
        else
          throw new ClipperException("Clipping error in SwapPositionsInAEL");
      }
      //------------------------------------------------------------------------------

      private void SwapPositionsInSEL(Active e1, Active e2)
      {
        Active next, prev;
        if (e1.NextInSEL == e2)
        {
          next = e2.NextInSEL;
          if (next != null) next.PrevInSEL = e1;
          prev = e1.PrevInSEL;
          if (prev != null) prev.NextInSEL = e2;
          e2.PrevInSEL = prev;
          e2.NextInSEL = e1;
          e1.PrevInSEL = e2;
          e1.NextInSEL = next;
          if (e2.PrevInSEL == null) SEL = e2;
        }
        else if (e2.NextInSEL == e1)
        {
          next = e1.NextInSEL;
          if (next != null) next.PrevInSEL = e2;
          prev = e2.PrevInSEL;
          if (prev != null) prev.NextInSEL = e1;
          e1.PrevInSEL = prev;
          e1.NextInSEL = e2;
          e2.PrevInSEL = e1;
          e2.NextInSEL = next;
          if (e1.PrevInSEL == null) SEL = e1;
        }
        else
          throw new ClipperException("Clipping error in SwapPositionsInSEL");
      }
      //------------------------------------------------------------------------------

      private Boolean ResetHorzDirection(Active horz, Active maxPair, 
        out cInt horzLeft, out cInt horzRight)
      {
        if (horz.Bot.X == horz.Top.X)
        {
        //the horizontal edge is going nowhere ...
        horzLeft = horz.Curr.X;
        horzRight = horz.Curr.X;
        Active e = horz.NextInAEL;
        while (e != null && e != maxPair) e = e.NextInAEL;
        return e != null;
      }
      else if (horz.Curr.X < horz.Top.X)
        {
          horzLeft = horz.Curr.X;
          horzRight = horz.Top.X;
          return true;
      }
      else
      {
        horzLeft = horz.Top.X;
        horzRight = horz.Curr.X;
        return false; //right to left
      }
    }
      //------------------------------------------------------------------------

    private void ProcessHorizontal(Active horz)
    /*******************************************************************************
    * Notes: Horizontal edges (HEs) at scanline intersections (ie at the top or    *
    * bottom of a scanbeam) are processed as if layered.The order in which HEs     *
    * are processed doesn't matter. HEs intersect with the bottom vertices of      *
    * other HEs[#] and with non-horizontal edges [*]. Once these intersections     *
    * are completed, intermediate HEs are 'promoted' to the next edge in their     *
    * bounds, and they in turn may be intersected[%] by other HEs.                 *
    *                                                                              *
    * eg: 3 horizontals at a scanline:    /   |                     /           /  *
    *              |                     /    |     (HE3)o ========%========== o   *
    *              o ======= o(HE2)     /     |         /         /                *
    *          o ============#=========*======*========#=========o (HE1)           *
    *         /              |        /       |       /                            *
    *******************************************************************************/
    {
      IntPoint pt;
      //with closed paths, simplify consecutive horizontals into a 'single' edge ...
      if (!IsOpen(horz))
      {
        pt = horz.Bot;
        while (!IsMaxima(horz) && NextVertex(horz).Pt.Y == pt.Y) 
          UpdateEdgeIntoAEL(ref horz);
        horz.Bot = pt;
        horz.Curr = pt;
      };

      Active maxPair = null;
      if (IsMaxima(horz) && (!IsOpen(horz) ||
          ((horz.VertTop.Flags & (VertexFlags.vfOpenStart | VertexFlags.vfOpenEnd)) == 0))) 
            maxPair = GetMaximaPair(horz);

      cInt horzLeft, horzRight;
      Boolean isLeftToRight = ResetHorzDirection(horz, maxPair, out horzLeft, out horzRight);
      if (IsHotEdge(horz)) AddOutPt(horz, horz.Curr);

      while (true) //loops through consec. horizontal edges (if open)
      {
        Active e;
        Boolean isMax = IsMaxima(horz);
        if (isLeftToRight)
          e = horz.NextInAEL; else
          e = horz.PrevInAEL;
        
        while (e != null)
        {
          //break if we've gone past the } of the horizontal ...
          if ((isLeftToRight && (e.Curr.X > horzRight)) ||
            (!isLeftToRight && (e.Curr.X < horzLeft))) break;
          //or if we've got to the } of an intermediate horizontal edge ...
          if (e.Curr.X == horz.Top.X && !isMax && !IsHorizontal(e))
          {
            pt = NextVertex(horz).Pt;
            if (isLeftToRight && (TopX(e, pt.Y) >= pt.X) ||
              (!isLeftToRight && (TopX(e, pt.Y) <= pt.X))) break;
          };

          if (e == maxPair)
          {
            if (IsHotEdge(horz))
              AddLocalMaxPoly(horz, e, horz.Top);
            DeleteFromAEL(e);
            DeleteFromAEL(horz);
            return;
          };

          if (isLeftToRight)
          {
            pt = new IntPoint(e.Curr.X, horz.Curr.Y);
            IntersectEdges(horz, e, pt);
          } else
          {
            pt = new IntPoint(e.Curr.X, horz.Curr.Y);
            IntersectEdges(e, horz, pt);
          };

          Active eNext;
          if (isLeftToRight)
            eNext = e.NextInAEL; else
            eNext = e.PrevInAEL;
          SwapPositionsInAEL(horz, e);
          e = eNext;
        }

        //check if we've finished with (consecutive) horizontals ...
        if (NextVertex(horz).Pt.Y != horz.Top.Y) break;

        //still more horizontals in bound to process ...
        UpdateEdgeIntoAEL(ref horz);
        ResetHorzDirection(horz, maxPair, out horzLeft, out horzRight);

        if (IsOpen(horz))
        {
          if (IsMaxima(horz)) maxPair = GetMaximaPair(horz);
          if (IsHotEdge(horz)) AddOutPt(horz, horz.Bot);
        }
      }

      if (IsHotEdge(horz)) AddOutPt(horz, horz.Top);

      if (IsOpen(horz))
      {
        if (!IsMaxima(horz))
          UpdateEdgeIntoAEL(ref horz);
        else if (maxPair != null)
          AddLocalMaxPoly(horz, maxPair, horz.Top);
        else
          DeleteFromAEL(horz);
      }
      else
        UpdateEdgeIntoAEL(ref horz); //this is the } of an intermediate horiz.
    }
    //------------------------------------------------------------------------------

    private void DoTopOfScanbeam(cInt Y)
    {
      Active e = Actives;
      while (e != null) 
      {
        //nb: E will never be horizontal at this point
        if (e.Top.Y == Y)
        {
          e.Curr = e.Top; //needed for horizontal processing
          if (IsMaxima(e)) 
          {
            e = DoMaxima(e); //TOP OF BOUND (MAXIMA)
            continue;
          }
          else
          {
            //INTERMEDIATE VERTEX ...
            UpdateEdgeIntoAEL(ref e);
            if (IsHotEdge(e))AddOutPt(e, e.Bot);
            if (IsHorizontal(e))
              PushHorz(e); //horizontals are processed later
          }
        }
        else
        {
          e.Curr.Y = Y;
          e.Curr.X = TopX(e, Y);
        }
        e = e.NextInAEL;
      }
    }
    //------------------------------------------------------------------------------

    private Active DoMaxima(Active e)
    {
      Active eNext, ePrev, eMaxPair;
      ePrev = e.PrevInAEL;
      eNext = e.NextInAEL;
      if (IsOpen(e) && ((e.VertTop.Flags & (VertexFlags.vfOpenStart | VertexFlags.vfOpenEnd)) != 0))
      {
        if (IsHotEdge(e)) AddOutPt(e, e.Top);
        if (IsHorizontal(e))
        {
          if (IsHotEdge(e)) TerminateHotOpen(e);
          DeleteFromAEL(e);
        }
        return eNext;
      } else
      {
        eMaxPair = GetMaximaPair(e);
        if (eMaxPair == null) return eNext; //eMaxPair is horizontal
      }

      //only non-horizontal maxima here.
      //process any edges between maxima pair ...
      while (eNext != eMaxPair)
      {
        IntersectEdges(e, eNext, e.Top);
        SwapPositionsInAEL(e, eNext);
        eNext = e.NextInAEL;
      }

      if (IsOpen(e))
      {
        if (IsHotEdge(e))
        {
          if (eMaxPair != null)
            AddLocalMaxPoly(e, eMaxPair, e.Top); else
            AddOutPt(e, e.Top);
        }
        if (eMaxPair != null)
          DeleteFromAEL(eMaxPair);
        DeleteFromAEL(e);
        return (ePrev != null ? ePrev.NextInAEL : Actives);
      }
      //here E.NextInAEL == ENext == EMaxPair ...
      if (IsHotEdge(e))
        AddLocalMaxPoly(e, eMaxPair, e.Top);

      DeleteFromAEL(e);
      DeleteFromAEL(eMaxPair);
      return (ePrev != null ? ePrev.NextInAEL : Actives);
    }
    //------------------------------------------------------------------------------

    private Int32 PointCount(OutPt op)
    {
      if (op == null) return 0;
      OutPt p = op;
      Int32 cnt = 0;
      do
      {
        cnt++;
        p = p.Next;
      } while (p != op);
      return cnt;
    }
    //------------------------------------------------------------------------------

    private void BuildResult(Paths closedPaths, Paths openPaths)
    {
      closedPaths.Clear();
      closedPaths.Capacity = OutRecList.Count;
      if (openPaths != null)
      {
        openPaths.Clear();
        openPaths.Capacity = OutRecList.Count;
      }

      foreach (OutRec outrec in OutRecList)
        if (outrec.Pts != null)
        {
          OutPt op = outrec.Pts.Prev;
          Int32 cnt = PointCount(op);
          //fixup for duplicate start and } points ...
          if (op.Pt == outrec.Pts.Pt) cnt--;

          if ((outrec.Flags & OutrecFlags.orOpen) > 0)
          {
            if (cnt < 1 || openPaths == null) continue;
            Path p = new Path(cnt);
            for (Int32 i = 0; i < cnt; i++) { p.Add(op.Pt); op = op.Prev; }
            openPaths.Add(p);
          }
          else
          {
            if (cnt < 2) continue;
            Path p = new Path(cnt);
            for (Int32 i = 0; i < cnt; i++) { p.Add(op.Pt); op = op.Prev; }
            closedPaths.Add(p);
          }
        }
    }
    //------------------------------------------------------------------------------

    private void BuildResult2(PolyTree pt, Paths openPaths)
    {
      if (pt == null) return;
      if (openPaths != null)
      {
        openPaths.Clear();
        openPaths.Capacity = OutRecList.Count;
      }

      foreach (OutRec outrec in OutRecList)
        if (outrec.Pts != null)
        {
            OutPt op = outrec.Pts.Prev;
            Int32 cnt = PointCount(op);
            //fixup for duplicate start and } points ...
            if (op.Pt == outrec.Pts.Pt) cnt--;

            if (cnt < 3)
            {
              if ((outrec.Flags & OutrecFlags.orOpen) == 0 || cnt < 2) continue;
            }

            Path p = new Path(cnt);
            for (Int32 i = 0; i < cnt; i++) { p.Add(op.Pt); op = op.Prev; }
            if ((outrec.Flags & OutrecFlags.orOpen) > 0)
              openPaths.Add(p);
            else
            {
              PolyPath pp =  (outrec.Owner != null ? outrec.Owner.PolyPath : pt);
              outrec.PolyPath = pp.AddChild(p);
            }
        }
    }
    //------------------------------------------------------------------------------
    
  } //Clipper2

  class ClipperException : Exception
  {
      public ClipperException(string description) : base(description){}
  }
  //------------------------------------------------------------------------------

} //ClipperLib namespace
