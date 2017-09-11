unit Clipper2_Misc;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  10.0 (alpha)                                                    *
* Date      :  9 September 2017                                                *
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
  SysUtils, Types, Classes, Math, Clipper2;

function Orientation(const path: TPath): Boolean; overload;
function Area(const path: TPath): double;

//PointInPolygon: 0=false; +1=true; -1 when 'pt' is on a polygon edge
function PointInPolygon(const pt: TPoint64; const path: TPath): integer;

function Path1ContainsPath2(const Path1, Path2: TPath): Boolean;
function PolyTreeToPaths(PolyTree: TPolyTree): TPaths;
function GetBounds(const paths: TPaths): TRect64;
function ReversePath(const path: TPath): TPath;
function ReversePaths(const paths: TPaths): TPaths;



implementation

//OVERFLOWCHECKS OFF is a necessary workaround for a Delphi compiler bug that very
//occasionally reports overflow errors while still returning correct values
//eg var A, B: Int64; begin A := -$13456780; B := -$73456789; A := A * B; end;
//see https://forums.embarcadero.com/message.jspa?messageID=871444
//nb: this issue was resolved in Delphi 10.2
{$OVERFLOWCHECKS OFF}

function Area(const path: TPath): double;
var
  i, j, cnt: integer;
  d: double;
begin
  Result := 0.0;
  cnt := Length(path);
  if (cnt < 3) then Exit;
  j := cnt - 1;
  for i := 0 to cnt -1 do
  begin
    d := (path[j].X + path[i].X);
    Result := Result + d * (path[j].Y - path[i].Y);
    j := i;
  end;
  Result := -Result * 0.5;
end;
//------------------------------------------------------------------------------

function Orientation(const path: TPath): Boolean;
begin
  Result := Area(path) >= 0;
end;
//------------------------------------------------------------------------------

function ReversePath(const path: TPath): TPath;
var
  i, highI: integer;
begin
  highI := high(path);
  SetLength(Result, highI +1);
  for i := 0 to highI do
    Result[i] := path[highI - i];
end;
//------------------------------------------------------------------------------

function ReversePaths(const paths: TPaths): TPaths;
var
  i, j, highJ: integer;
begin
  i := length(paths);
  SetLength(Result, i);
  for i := 0 to i -1 do
  begin
    highJ := high(paths[i]);
    SetLength(Result[i], highJ+1);
    for j := 0 to highJ do
      Result[i][j] := paths[i][highJ - j];
  end;
end;
//------------------------------------------------------------------------------

function GetBounds(const paths: TPaths): TRect64;
var
  I,j, len: integer;
begin
  len := Length(paths);
  I := 0;
  while (I < len) and (Length(paths[I]) = 0) do inc(I);
  if (I = len) then
  begin
    Result := EmptyRect;
    Exit;
  end;
  Result.Left := paths[I][0].X;
  Result.Right := Result.Left;
  Result.Top := paths[I][0].Y;
  Result.Bottom := Result.Top;
  for I := I to len -1 do
    for j := 0 to High(paths[I]) do
    begin
      if paths[I][j].X < Result.Left then Result.Left := paths[I][j].X
      else if paths[I][j].X > Result.Right then Result.Right := paths[I][j].X;
      if paths[I][j].Y < Result.Top then Result.Top := paths[I][j].Y
      else if paths[I][j].Y > Result.Bottom then Result.Bottom := paths[I][j].Y;
    end;
end;
//------------------------------------------------------------------------------

function PointInPolygon(const pt: TPoint64; const path: TPath): integer;
var
  i, cnt: integer;
  d, d2, d3: double; //nb: double not cInt to avoid potential overflow errors
  ip, ipNext: TPoint64;
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

function Path1ContainsPath2(const Path1, Path2: TPath): Boolean;
var
  i: integer;
  pt: TPoint64;
begin
  //precondition: Path2 may touch but not intersect Path1.
  result := false;
  if (length(Path1) < 3) or (length(Path2) = 0) then Exit;
  for i := 0 to high(Path2) do
  begin
    pt := Path2[i];
    //nb: PointInPolygon returns 0 if false, +1 if true, -1 if pt on polygon
    case PointInPolygon(pt, Path1) of
      0: Exit;
      1: begin Result := true; Exit; end;
      //else point on line
    end;
  end;
  result := true; //ie no vertex in Path2 is outside Path1.
end;
//---------------------------------------------------------------------------

procedure AddPolyNodeToPaths(Poly: TPolyPath; var Paths: TPaths);
var
  i: integer;
begin
  if (Length(Poly.Path) > 0) then
  begin
    i := Length(Paths);
    SetLength(Paths, i +1);
    Paths[i] := Poly.Path;
  end;

  for i := 0 to Poly.ChildCount - 1 do
    AddPolyNodeToPaths(Poly.Child[i], Paths);
end;
//------------------------------------------------------------------------------

function PolyTreeToPaths(PolyTree: TPolyTree): TPaths;
begin
  Result := nil;
  AddPolyNodeToPaths(PolyTree, Result);
end;
//------------------------------------------------------------------------------

end.
