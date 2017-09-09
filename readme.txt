
Clipper2 (9 September 2017)


This is a preview of a major update that I'm working on (very slowly). While the code in previous version was functional, in many places it is/was downright ugly and needed to be rewritten. This new version is also a little quicker. However, at the moment this new version only performs the "bare bones" of the clipping library - there's no merging of polygons with common/touching edges in clip solutions (though this was always incomplete). There's also no 'offseting' code yet.


There are also quite a few changes to public methods in the libary's classes. Here are the more notable ones ...
1. Execute parameters have changed: an optional OpenPaths parameter has been added; and there's now only one PolyFillType parameter. (On reflection it seemed unnecessary complicated to have separate PolyFillType parameter for Subject and Clip paths.)
2. The PolyFillType enumeration has been renamed FillType.
3. The Polytree class now only contains closed paths (ie polygons) since only polygons can contain/own other polygons. (Open paths are now returned via a separate Paths parameter in Execute.)
4. I've renamed the Closed parameters in AddPath and AddPaths to IsOpen (and it now defaults to false).
5. There's no longer an additional restriction on the size of Int64 values used for path coordinates (excluding the obvious limitation of the 64bit structure).



Below I've benchmarked a few comparisons between the old (ver 6.4.2) and this Clipper. (The old version has also had the polygon 'merging' code removed so we're comparing 'apples with apples'. Tests were compiled (for 32bit) using Delphi 10.1 and performed using Windows 10 64Bit with Intel i7 2.0GHz CPU and 8GB RAM.

TEST1: Time (secs) to intersect a single random subject and clip COMPLEX polygon (using evenodd filling).
+===================+=========+=========+=======+
|No. Edges          | New     | Old     | Perf. |
|(each)             | Clipper | Clipper | Incr. |  
+===================+=========+=========+=======+
|2000               | 4.40    |  5.85   | 33%   |
|2500               | 11.0    |  13.9   | 24%   |
|3000               | 24.2    |  35.7   | 48%   |
|3500               | 52.5    |  73.0   | 40%   |
|4000               | 98.8    |  138.3  | 40%   |
|4500               |         |         |       |
|5000               | 273.4   |  326.4  | 20%   |
+===================+=========+=========+=======+
Vertex coordinate ranges X:0-800, Y:0-600 (rounded to nearest 10).

TEST2: Time (secs) to intersect multiple random subject and clip ELLIPSE polygons.
+===================+=========+=========+=======+
|No. Ellipses       | New     | Old     | Perf. |
|(each)             | Clipper | Clipper | Incr. |
+===================+=========+=========+=======+
|100                | 0.0049  | 0.0069  | 40%   |
|500                | 0.09    | 0.15    | 66%   |
|1000               | 0.456   | 0.88    | 90%   |
|2000               | 4.6     | 9.3     | 100%  |
+===================+=========+=========+=======+
Paths approximating ellipses are such that the edges deviate from the true elliptical path by <= 1/2px. Random ellipses are bounded by range X:0-800, Y:0-600 where the max. elliptical radii are 1/3 of axis bounds and the min. radii is 10.
