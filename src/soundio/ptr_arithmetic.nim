
template `+`*[T](p: ptr T, off: SomeInteger): ptr T =
  cast[ptr type(p[])](cast[uint](p) + (off.uint * sizeof(p[]).uint))

template `+=`*[T](p: ptr T, off: int) =
  p = p + off

template `-`*[T](p: ptr T, off: SomeInteger): ptr T =
  cast[ptr type(p[])](cast[uint](p) - (off.uint * sizeof(p[]).uint))

template `-=`*[T](p: ptr T, off: int) =
  p = p - off

template `[]`*[T](p: ptr T, off: int): T =
  (p + off)[]

template `[]=`*[T](p: ptr T, off: int, val: T) =
  (p + off)[] = val