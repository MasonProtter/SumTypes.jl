# SumTypes.jl

- [Basics](https://github.com/MasonProtter/SumTypes.jl#basics)
- [Destructuring sum types](https://github.com/MasonProtter/SumTypes.jl#destructuring-sum-types)
- [Avoiding namespace clutter](https://github.com/MasonProtter/SumTypes.jl#avoiding-namespace-clutter)
- [Custom printing](https://github.com/MasonProtter/SumTypes.jl#custom-printing)
- [Performance](https://github.com/MasonProtter/SumTypes.jl#performance)


## Basics

<!-- <details> -->
<!-- <summary>Click to expand</summary> -->

Sum types, sometimes called 'tagged unions' are the type system equivalent 
of the [disjoint union](https://en.wikipedia.org/wiki/Disjoint_union) operation (which is *not* a union in the 
traditional sense). In the [Rust programming language](https://doc.rust-lang.org/book/ch06-00-enums.html), these
are called "Enums", and they're more general than what Julia calls an 
[enum](https://docs.julialang.org/en/v1/base/base/#Base.Enums.@enum).

At the end of the day, a sum type is really just a fancy word for a container that can store data of a few 
different, pre-declared types and is labelled by how it was instantiated.

Users of statically typed programming languages often prefer Sum types to unions because it makes type checking 
easier. In a dynamic language like julia, the benefit of these objects is less obvious, but there are cases where
they're helpful, like performance sensitive branching on heterogeneous types, and enforcing the handling of cases.

The simplest version of a sum type is just a list of constant variants (i.e. basically a 
[julia enum](https://docs.julialang.org/en/v1/base/base/#Base.Enums.@enum)):
```julia
using SumTypes

@sum_type Fruit begin
    apple
    banana
    orange
end
```
```julia
julia> apple
apple::Fruit

julia> banana
banana::Fruit

julia> orange
brange::Fruit

julia> typeof(apple) == typeof(banana) == typeof(orange) <: Fruit
true
```

But this isn't particularly interesting. More interesting are sum types which can **enclose data**. 
Let's explore a very fundamental sum type (fundamental in the sense that all other sum types may be derived from it):

```julia
@sum_type Either{A, B} begin
    Left{A}(::A)
    Right{B}(::B)
end
```
This says that we have a sum type `Either{A, B}`, and it can hold a value that is either of type `A` or of type `B`. `Either` has two
'constructors' which we have called `Left{A}` and `Right{B}`. These exist essentially as a way to have instances of `Either` carry 
a record of how they were constructed by being wrapped in dummy structs named `Left` or `Right`. 

Here is how these constructors behave:
```julia
julia> Left(1)
Left(1)::Either{Int64, Uninit}

julia> Right(1.0)
Right(1.0)::Either{Uninit, Float64}
```
Notice that because both `Left{A}` and `Right{B}` each carry one fewer type parameter than `Either{A,B}`, then simply writing
`Left(1)` is *not enough* to fully specify the type of the full `Either`, so the unspecified field is `SumTypes.Uninit` by default.

In cases like this, you can rely on *implicit conversion* to get the fully initialized type. E.g.
```julia
julia> let x::Either{Int, Float64} = Left(1)
           x
       end
Left(1)::Either{Int64, Float64}
```
Typically, you'll do this by enforcing a return type on a function:
``` julia
function foo() :: Either{Int, Float64}
    # Randomly return either a Left(1) or a Right(2.0)
    rand(Bool) ? Left(1) : Right(2.0)
end;
```
```julia
julia> foo()
Left(1)::Either{Int64, Float64}

julia> foo()
Right(2.0)::Either{Int64, Float64}
```
This is particularly useful because in this case `foo` is 
[type stable](https://docs.julialang.org/en/v1/manual/performance-tips/#Write-%22type-stable%22-functions)!

``` julia
julia> Base.return_types(foo, Tuple{})
1-element Vector{Any}:
 Either{Int64, Float64, 8, 0, UInt64}

julia> isconcretetype(ans[1])
true
```
Note that unlike `Union{A, B}`, `A <: Either{A,B}` is false, and `Either{A, A}` is distinct from `A`.

<!-- </details> -->


## Destructuring Sum types
<!-- <details> -->
<!-- <summary>Click to expand</summary> -->

Okay, but how do I actually access the data enclosed in a `Fruit` or an `Either`? The answer is destructuring. 
SumTypes.jl exposes a `@cases` macro for efficiently unwrapping and branching on the contents of a sum type:

```julia
julia> myfruit = orange
orange::Fruit

julia> @cases myfruit begin
           apple => "Got an apple!"
           orange => "Got an orange!"
           banana => error("I'm allergic to bananas!")
       end
"Got an orange!"

julia> @cases banana begin
           apple => "Got an apple!"
           orange => "Got an orange!"
           banana => error("I'm allergic to bananas!")
       end
ERROR: I'm allergic to bananas!
[...]
``` 
`@cases` can automatically detect if you didn't give an exhaustive set of cases (with no runtime penalty) and throw an error.
```julia
julia> @cases myfruit begin
           apple => "Got an apple!"
           orange => "Got an orange!"
       end
ERROR: Inexhaustive @cases specification. Got cases (:apple, :orange), expected (:apple, :banana, :orange)
[...]
```

Furthermore, `@cases` can *destructure* sum types which hold data:

``` julia
julia> let x::Either{Int, Float64} = rand(Bool) ? Left(1) : Right(2.0)
           @cases x begin
               Left(l) => l + 1.0
               Right(r) => r - 1
           end
       end
2.0
```
i.e. in this example, `@cases` took in an `Either{Int,Float64}` and if it contained a `Left`, it took the wrapped data (an `Int`) 
bound it do the variable `l` and added `1.0` to `l`, whereas if it was a `Right`, it took the `Float64` and bound it to a variable 
`r` and subtracted `1` from `r`.

The `@cases` macro still falls far short of a full on pattern matching system, lacking many features. For anything advanced, I'd recommend using `@match` from [MLStyle.jl](https://github.com/thautwarm/MLStyle.jl).

### Defining many repetitive cases simultaneously 

`@cases` does not allow for fallback branches, and it also does not allow one to write inexhaustive cases. To avoid making some code overly verbose and repetitive, we instead provide syntax for defining many cases in one line:

``` julia
@sum_type Re begin
    Empty
    Class(::UInt8)
    Rep(::Re)
    Alt(::Re, ::Re)
    Cat(::Re, ::Re)
    Diff(::Re, ::Re)
    And(::Re, ::Re)
end;

isEmpty(x::Re) = @cases x begin
    Empty => true
    [Class, Rep, Alt, Cat, Diff, And] => false
end
```

This is the same as if one had manually written out

``` julia
isEmpty(r::Re) = @cases r begin
    Empty => true
    Class => false
    Rep => false
    Alt => false
    Cat => false
    Diff => false
    And => false
end
```

You can also destructure repeated cases with the `[]` syntax:

``` julia
count_classes(r::Re, c=0) = @cases r begin
    Empty => c
    Class => c + 1
    Rep(x) => c + count_classes(x)
   [Alt, Cat, Diff, And](x, y)  => c + count_classes(x) + count_classes(y)
end;
```

<!-- </details> -->


## Avoiding namespace clutter

<details>
<summary>Click to expand</summary>

A common complaint about Enums and Sum Types is that sometimes they can contribute to clutter in the namespace. If you want to avoid having all the variants being available as top-level constant variables, then you can use the `:hidden` option:

``` julia
julia> @sum_type Foo{T} :hidden begin
           A
           B{T}(::T)
       end

julia> A
ERROR: UndefVarError: A not defined

julia> B
ERROR: UndefVarError: B not defined
```
These 'hidden' variants can be accessed by applying the `'` operator to the type `Foo`, which returns a named tuple of the variants:

``` julia
julia> Foo'
(A = A::Foo{Uninit}, B = var"#Foo#B")
```
And then you can access this named tuple as normal:
``` julia

julia> Foo'.A
A::Foo{Uninit}

julia> Foo'.B(1)
B(1)::Foo{Int64}
```

You can even do fancy things like

``` julia
julia> let (; B) = Foo'
           B(1)
       end
B(1)::Foo{Int64}
```
Note that property-destructuring syntax is only available on julia version 1.7 and higher https://github.com/JuliaLang/julia/issues/39285

</details>


## Custom printing

<details>
<summary>Click to expand</summary>

SumTypes.jl automatically overloads `Base.show(::IO, ::YourType)` and `Base.show(::IO, ::MIME"text/plain", ::YourType)` 
for your type when you create a sum type, but it forwards that call to an internal function `SumTypes.show_sumtype`. If 
you wish to customize the printing of a sum type, then you should overload `SumTypes.show_sumtype`:
``` julia
julia> @sum_type Fruit2 begin
           apple
           orange
           banana
       end;

julia> apple
apple::Fruit2

julia> SumTypes.show_sumtype(io::IO, x::Fruit2) = @cases x begin
           apple => print(io, "apple")
           orange => print(io, "orange")
           banana => print(io, "banana")
       end

julia> apple
apple

julia> SumTypes.show_sumtype(io::IO, ::MIME"text/plain", x::Fruit2) = @cases x begin
           apple => print(io, "apple!")
           orange => print(io, "orange!")
           banana => print(io, "banana!")
       end

julia> apple
apple!
```
If you overload `Base.show` directly inside a package, you might get annoying method deletion warnings during pre-compilation.

</details>

## Performance

SumTypes.jl can provide some speedups compared to union-splitting when destructuring and branching on abstractly typed data.

#### SumTypes.jl

<details>
<summary>Benchmark code</summary>

``` julia
module SumTypeTest

using SumTypes,  BenchmarkTools
@sum_type AT begin
    A(common_field::Int, a::Bool, b::Int)
    B(common_field::Int, a::Int, b::Float64, d::Complex)
    C(common_field::Int, b::Float64, d::Bool, e::Float64, k::Complex{Real})
    D(common_field::Int, b::Any)
end

foo!(xs) = for i in eachindex(xs)
    xs[i] = @cases xs[i] begin
        A(cf, a, b)       => B(cf+1, a, b, b)
        B(cf, a, b, d)    => C(cf-1, b, isodd(a), b, d)
        C(cf, b, d, e, k) => D(cf+1, isodd(cf) ? "hi" : "bye")
        D(cf, b)          => A(cf-1, b=="hi", cf)
    end
end

xs = rand((A(1, true, 10), 
           B(1, 1, 1.0, 1+1im), 
           C(1, 2.0, false, 3.0, Complex{Real}(1 + 2im)), 
           D(1, "hi")), 
	      10000);

display(@benchmark foo!($xs);)

end
```

</details>

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  300.541 μs …   2.585 ms  ┊ GC (min … max): 0.00% … 86.91%
 Time  (median):     313.611 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   342.285 μs ± 242.158 μs  ┊ GC (mean ± σ):  8.29% ± 10.04%

  █                                                             ▁
  █▇▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ █
  301 μs        Histogram: log(frequency) by time       2.37 ms <

 Memory estimate: 620.88 KiB, allocs estimate: 19900.
```


#### Branching on abstractly typed data:

<details>
<summary>Benchmark code</summary>

``` julia
module AbstractTypeTest

using BenchmarkTools

abstract type AT end
Base.@kwdef struct A <: AT
    common_field::Int
    a::Bool 
    b::Int
end
Base.@kwdef struct B <: AT
    common_field::Int
    a::Int
    b::Float64 
    d::Complex  # not isbits
end
Base.@kwdef struct C <: AT
    common_field::Int
    b::Float64 
    d::Bool 
    e::Float64
    k::Complex{Real}  # not isbits
end
Base.@kwdef struct D <: AT
    common_field::Int
    b::Any  # not isbits
end

foo!(xs) = for i in eachindex(xs)
    @inbounds x = xs[i]
    @inbounds xs[i] = x isa A ? B(x.common_field+1, x.a, x.b, x.b) :
        x isa B ? C(x.common_field-1, x.b, isodd(x.a), x.b, x.d) :
        x isa C ? D(x.common_field+1, isodd(x.common_field) ? "hi" : "bye") :
        x isa D ? A(x.common_field-1, x.b=="hi", x.common_field) : error()
end


xs = rand((A(1, true, 10), 
           B(1, 1, 1.0, 1+1im), 
           C(1, 2.0, false, 3.0, Complex{Real}(1 + 2im)), 
           D(1, "hi")), 
	      10000);
display(@benchmark foo!($xs);)

end
```

</details>

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  366.510 μs …   4.504 ms  ┊ GC (min … max):  0.00% … 90.65%
 Time  (median):     386.470 μs               ┊ GC (median):     0.00%
 Time  (mean ± σ):   478.369 μs ± 571.525 μs  ┊ GC (mean ± σ):  18.62% ± 13.77%

  █                                                           ▂ ▁
  █▇▄▅▅▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ █
  367 μs        Histogram: log(frequency) by time        4.1 ms <

 Memory estimate: 1.06 MiB, allocs estimate: 31958.
```

#### Unityper.jl 

Unityper.jl is a somewhat similar package, with some overlapping goals to SumTypes.jl. However, In this test, Unityper.jl ends up doing much worse than abstract containers or SumTypes.jl:

<details>
<summary>Benchmark code</summary>

``` julia

module UnityperTest

using Unityper, BenchmarkTools

@compactify begin
    @abstract struct AT
        common_field::Int = 0
    end
    struct A <: AT
        a::Bool = true
        b::Int = 10
    end
    struct B <: AT
        a::Int = 1
        b::Float64 = 1.0
        d::Complex = 1 + 1.0im # not isbits
    end
    struct C <: AT
        b::Float64 = 2.0
        d::Bool = false
        e::Float64 = 3.0
        k::Complex{Real} = 1 + 2im # not isbits
    end
    struct D <: AT
        b::Any = "hi" # not isbits
    end
end

foo!(xs) = for i in eachindex(xs)
    @inbounds x = xs[i]
    @inbounds xs[i] = @compactified x::AT begin
        A => B(;common_field=x.common_field+1, a=x.a, b=x.b, d=x.b)
        B => C(;common_field=x.common_field-1, b=x.b, d=isodd(x.a), e=x.b, k=x.d)
        C => D(;common_field=x.common_field+1, b=isodd(x.common_field) ? "hi" : "bye")
        D => A(;common_field=x.common_field-1, a=x.b=="hi", b=x.common_field)
    end
end

xs = rand((A(), B(), C(), D()), 10000);
display(@benchmark foo!($xs);)

end
```

</details>

```
BenchmarkTools.Trial: 2539 samples with 1 evaluation.
 Range (min … max):  1.847 ms …   5.341 ms  ┊ GC (min … max): 0.00% … 64.05%
 Time  (median):     1.890 ms               ┊ GC (median):    0.00%
 Time  (mean ± σ):   1.968 ms ± 478.604 μs  ┊ GC (mean ± σ):  3.93% ±  9.68%

  █▆
  ██▇▆▁▃▁▁▃▁▃▁▁▁▁▁▃▁▁▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▅▆▆▆▇ █
  1.85 ms      Histogram: log(frequency) by time       4.9 ms <

 Memory estimate: 1.14 MiB, allocs estimate: 27272.
```

SumTypes.jl has some other advantages relative to Unityper.jl such as:
- SumTypes.jl allows [parametric types](https://docs.julialang.org/en/v1/manual/types/#Parametric-Types) for much greater container flexibility.
- SumTypes.jl does not require default values for every field of the struct.
- SumTypes.jl's `@cases` macro is more powerful and flexible than Unityper's `@compactified`.
- SumTypes.jl allows you to hide its variants from the namespace (opt in).

One advantage of Unityper.jl is:
- If you're not modifying the data and just re-using old heap allocated data, there are cases where Unityper.jl can avoid an allocation that SumTypes.jl would have incurred.
