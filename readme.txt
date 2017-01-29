Clipper2 (30 January 2017)
This is just a preview of a major update I'm (slowly) working on. 
This new version currently performs only the "bare bones" of the clipping algorithm. 
It's "bare bones" because there's no merging of polygons that have common/touching edges in the clip solutions.
The merging of adjacent/touching polygons is/was incomplete and cumbersome in the earlier versions and needs to be completely rewritten.

Performance is a little faster than earlier versions. Below are 2 benchmark test comparisons between the Old and New Clipper. The Old Clipper (version 6.4.2) has had its solution merging code removed in order to compare 'apples with apples'. Tests were performed using Windows 10 64Bit with Intel i7 2.0GHz CPU and 8GB RAM.

TEST1: Time (secs) to intersect a single random subject and clip COMPLEX polygon.
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
