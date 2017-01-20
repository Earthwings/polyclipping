Clipper2 (20 January 2017)
This is just a preview of a major update I'm working on (very slowly). 
This new version currenty only performs the "bare bones" of the clipping algorithm. 
It's "bare bones" because no attempt is made to merge polygons in clipping solutions which have common / touching edges. This is still in the works.
(The merging of adjacent/touching polygons in clipping solutions is/was incomplete and cumbersome in the earlier versions of Clipper and this is being completely rewritten.)
While allowing for this missing polygon merging code, performance has modestly improved and the new version is about 10-15% faster than earlier versions.
