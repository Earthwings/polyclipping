/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  25 September 2017                                               *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2017                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************/

#ifndef clipper_h
#define clipper_h

#define CLIPPER_VERSION "10.0.0"

#include <vector>
#include <list>
#include <set>
#include <stdexcept>
#include <cstring>
#include <cstdlib>
#include <ostream>
#include <functional>
#include <queue>

namespace clipperlib {

enum ClipType { kIntersection, kUnion, kDifference, kXor };
enum PathType { kSubject, kClip };
enum FillRule { kEvenOdd, kNonZero, kPositive, kNegative };

struct Point64 {
  int64_t x;
  int64_t y;
  Point64(int64_t x = 0, int64_t y = 0): x(x), y(y) {};

  friend inline bool operator== (const Point64 &a, const Point64 &b)
  {
    return a.x == b.x && a.y == b.y;
  }
  friend inline bool operator!= (const Point64 &a, const Point64 &b) //todo: remove
  {
    return a.x != b.x || a.y != b.y;
  }
};

typedef std::vector< Point64 > Path;
typedef std::vector< Path > Paths;

inline Path& operator <<(Path &path, const Point64 &pt) {path.push_back(pt); return path;}
inline Paths& operator <<(Paths &paths, const Path &path) {paths.push_back(path); return paths;}

std::ostream& operator <<(std::ostream &s, const Point64 &p);
std::ostream& operator <<(std::ostream &s, const Path &p);
std::ostream& operator <<(std::ostream &s, const Paths &p);


class PolyPath
{ 
  private:
	  PolyPath *parent_;
	  Path path_;
	  std::vector< PolyPath* > childs_;
  public:
	  PolyPath(PolyPath *parent, const Path &path);
	  virtual ~PolyPath(){};
    PolyPath &AddChild(const Path &path);
	  PolyPath& GetChild(unsigned index);
    int ChildCount() const;
    PolyPath* GetParent() const;
	  Path& GetPath();
	  bool IsHole() const;
	  void Clear();
};

class PolyTree : public PolyPath {};

struct Rect64 { 
	int64_t left; 
	int64_t top; 
	int64_t right; 
	int64_t bottom; 
  Rect64(int64_t l, int64_t t, int64_t r, int64_t b) : left(l), top(t), right(r), bottom(b) {}
};

struct Active;
struct OutRec;
struct Vertex;
struct OutPt;
struct LocalMinima;
struct Scanline;
struct IntersectNode;

class Clipper {
  private:
    typedef std::vector < OutRec* > OutRecList;
	  typedef std::vector < IntersectNode* > IntersectList;
	  typedef std::priority_queue< int64_t > ScanlineList;
    typedef std::vector< LocalMinima* > MinimaList;
    typedef std::vector< Vertex* > VerticesList;

	  ClipType          cliptype_;
	  Active	         *actives_;
	  Active           *sel_;
	  bool              locked_;
    bool			        has_open_paths_;
    MinimaList        minima_list_;
    MinimaList::iterator curr_loc_min_;
    bool			        minima_list_sorted_;
    FillRule          filltype_;
    OutRecList		    outrec_list_;
    IntersectList     intersect_list_;
    VerticesList      vertex_list_;
    ScanlineList		  scanline_list_;
    void CleanUp();
    void Reset();
    void InsertScanline(int64_t y);
    bool PopScanline(int64_t &y);
    bool PopLocalMinima(int64_t y, LocalMinima *&local_minima);
    void DisposeAllOutRecs();
    void DisposeVerticesAndLocalMinima();
    void AddLocMin(Vertex &vert, PathType polytype, bool is_open);
    void AddPathToVertexList(const Path &p, PathType polytype, bool is_open);
    bool IsContributingClosed(const Active &e) const;
    inline bool IsContributingOpen(const Active &e) const;
    void SetWindingLeftEdgeClosed(Active &edge);
    void SetWindingLeftEdgeOpen(Active &e);
    void InsertEdgeIntoAEL(Active &edge, Active *startEdge, bool prefer_left);
    void InsertLocalMinimaIntoAEL(int64_t bot_y);
    inline void Clipper::PushHorz(Active &e);
    inline bool Clipper::PopHorz(Active *&e);
    OutRec* Clipper::GetOwner(const Active *e);
    void AddLocalMinPoly(Active &e1, Active &e2, const Point64 pt);
    void AddLocalMaxPoly(Active &e1, Active &e2, const Point64 pt);
    void JoinOutrecPaths(Active &e1, Active &e2);
    inline void TerminateHotOpen(Active &e);
    void AddOutPt(Active &e, const Point64 pt);
    void StartOpenPath(Active &e, const Point64 pt);
    inline void UpdateEdgeIntoAEL(Active *e);
    void IntersectEdges(Active &e1, Active &e2, const Point64 pt);
    inline void DeleteFromAEL(Active &e);
    inline void CopyAELToSEL();
    bool ExecuteInternal(ClipType ct, FillRule ft);
    void ProcessIntersections(const int64_t top_y);
    inline void DisposeIntersectNodes();
    void InsertNewIntersectNode(Active &e1, Active &e2, const int64_t top_y);
    void BuildIntersectList(const int64_t top_y);
    bool ProcessIntersectList();
    void FixupIntersectionOrder();
    void SwapPositionsInAEL(Active &edge1, Active &edge2);
    void SwapPositionsInSEL(Active &edge1, Active &edge2);
    void Insert2Before1InSel(Active &first, Active &second);
    bool ResetHorzDirection(Active &horz, Active *max_pair, int64_t &horz_left, int64_t &horz_right);
    void ProcessHorizontal(Active &horz);
    void DoTopOfScanbeam(const int64_t top_y);
    Active* DoMaxima(Active &e);
    void BuildResult(Paths &paths_closed, Paths *paths_open);
    void BuildResult2(PolyTree &pt, Paths *solution_open);  
  public:
	  Clipper();
	  ~Clipper();
	  void AddPath(const Path &path, PathType polytype, bool is_open = false);
    void AddPaths(const Paths &paths, PathType polytype, bool is_open = false);
    bool Execute(ClipType clipType, Paths &solution_closed, FillRule ft = kEvenOdd);
    bool Execute(ClipType clipType, Paths &solution_closed, Paths &solution_open, FillRule ft = kEvenOdd);
    bool Execute(ClipType clipType, PolyTree &solution_closed, Paths &solution_open, FillRule ft = kEvenOdd);
    void Clear();
    Rect64 Clipper::GetBounds();
};
//------------------------------------------------------------------------------

class ClipperException : public std::exception
{
  public:
    ClipperException(const char* description): descr_(description) {}
    virtual ~ClipperException() throw() {}
    virtual const char* what() const throw() {return descr_.c_str();}
  private:
    std::string descr_;
};
//------------------------------------------------------------------------------

} //clipperlib namespace

#endif //clipper_h


