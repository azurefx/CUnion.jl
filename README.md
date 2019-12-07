# CUnion.jl

[![Build Status](https://travis-ci.org/azurefx/CUnion.jl.svg?branch=master)](https://travis-ci.org/azurefx/CUnion.jl)

This package provides C-style primitive union types for Julia.

## Usage

Add the macro `@union` to a `struct` definition to make a C union:

```julia
@union struct U
  x::UInt8
  y::UInt16
end
```

Then `U` can be instantiated with one of its field types:

```julia
julia> u = U(Int8(-1))
U1(0x00ff)

julia> u1.y
0x00ff

julia> reinterpret(Int16, u)
255
```

Nested anonymous structs are also supported. For example, the `LARGE_INTEGER` type from Win32
```cpp
typedef union _LARGE_INTEGER {
  struct {
    DWORD LowPart;
    LONG HighPart;
  } DUMMYSTRUCTNAME;
  struct {
    DWORD LowPart;
    LONG HighPart;
  } u;
  LONGLONG QuadPart;
} LARGE_INTEGER;
```
Can be written as
```julia
@union struct LargeInteger
  struct u
    low::UInt32
    high::UInt32
  end
  quad::UInt64
end
```
```julia
julia> li=LargeInteger(0x00112233aabbccdd)
LargeInteger(0x00112233aabbccdd)

julia> li.u.high
0x00112233
```

## TODO

1. Improved reinterpret_cast performance?
2. Convenient methods to update fields?
3. Sub-typing and generic support?
