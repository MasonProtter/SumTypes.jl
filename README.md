# SumTypes.jl

- [Basics](https://github.com/MasonProtter/SumTypes.jl#basics)
- [Destructuring sum types](https://github.com/MasonProtter/SumTypes.jl#destructuring-sum-types)
- [Using `full_type` to get the concrete type of a Sum Type](https://github.com/MasonProtter/SumTypes.jl/#using-full_type-to-get-the-concrete-type-of-a-sum-type)
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
julia> @sum_type Fruit begin
           apple
           banana
           orange
       end

julia> apple
apple::Fruit

julia> banana
banana::Fruit

julia> orange
brange::Fruit

julia> typeof(apple) == typeof(banana) == typeof(orange) <: Fruit
true
```

But this isn't particularly interesting. More intesting is sum types which can **enclose data**. 
Let's explore a very fundamental sum type (fundamental in the sense that all other sum types may be derived from it):

```julia
julia> using SumTypes

julia> @sum_type Either{A, B} begin
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
``` julia
julia> let x::Either{Int, Float64} = Left(1)
           x
       end
Left(1)::Either{Int64, Float64}
```
Typically, you'll do this by enforcing a return type on a function:
``` julia
julia> function foo() :: Either{Int, Float64}
           # Randomly return either a Left(1) or a Right(2.0)
           rand(Bool) ? Left(1) : Right(2.0)
       end;

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
julia> myfruit = Orange
Orange::Fruit

julia> @cases myfruit begin
           Apple => "Got an apple!"
           Orange => "Got an orange!"
           Banana => error("I'm allergic to bananas!")
       end
"Got an orange!"

julia> @cases Banana begin
           Apple => "Got an apple!"
           Orange => "Got an orange!"
           Banana => error("I'm allergic to bananas!")
       end
ERROR: I'm allergic to bananas!
[...]
``` 
`@cases` can automatically detect if you didn't give an exhaustive set of cases (with no runtime penalty) and throw an error.
```julia
julia> @cases myfruit begin
           Apple => "Got an apple!"
           Orange => "Got an orange!"
       end
ERROR: Inexhaustive @cases specification. Got cases (:Apple, :Orange), expected (:Apple, :Banana, :Orange)
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

### Defining many repretitive cases simultaneously 

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

isempty(x::Re) = @cases x begin
	Empty => true
	[Class, Rep, Alt, Cat, Diff, And] => false
end
```

This is the same as if one had manually written out

``` julia
isempty(r::Re) = @cases r begin
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

## Using `full_type` to get the concrete type of a Sum Type

<details>
<summary>Click to expand</summary>

SumTypes.jl generates structs with a compactified memory layout which is computed on demand for parametric types. Because of this, 
every SumTypes actually has two extra type parameters related to its memory layout. This means that for instance, with `Either{Int, Int}`:

``` julia
julia> @sum_type Either{A, B} begin
           Left{A}(::A)
           Right{B}(::B)
       end

julia> isconcretetype(Either{Int, Int})
false
```

In order to get the proper, concrete type corresponding to `Either{Int, Int}`, one can use the `full_type` function exported by SumTypes.jl:

``` julia
julia> full_type(Either{Int, Int})
Either{Int64, Int64, 8, 0, UInt64}

julia> full_type(Either{Int, String})
Either{Int64, String, 8, 1, UInt8}

julia> full_type(Either{Tuple{Int, Int, Int}, String})
Either{Tuple{Int64, Int64, Int64}, String, 24, 1, UInt8}

julia> isconcretetype(ans)
true
```

Avoiding these extra parameters would require https://github.com/JuliaLang/julia/issues/8472 to be implemented.

</details>


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

In the same way as [Unityper.jl](https://github.com/YingboMa/Unityper.jl) is able to provide a dramatic speedup versus manual union splitting, SumTypes.jl can do this too:

Branching on abstractly typed data

<details>
<summary>Benchmark code</summary>

``` julia
module AbstractTypeTest

using BenchmarkTools

abstract type AT end
Base.@kwdef struct A <: AT
    common_field::Int = 0
    a::Bool = true
    b::Int = 10
end
Base.@kwdef struct B <: AT
    common_field::Int = 0
    a::Int = 1
    b::Float64 = 1.0
    d::Complex = 1 + 1.0im # not isbits
end
Base.@kwdef struct C <: AT
    common_field::Int = 0
    b::Float64 = 2.0
    d::Bool = false
    e::Float64 = 3.0
    k::Complex{Real} = 1 + 2im # not isbits
end
Base.@kwdef struct D <: AT
    common_field::Int = 0
    b::Any = :hi # not isbits
end

foo!(xs) = for i in eachindex(xs)
    @inbounds x = xs[i]
    @inbounds xs[i] = x isa A ? B() :
                      x isa B ? C() :
                      x isa C ? D() :
                      x isa D ? A() : error()
end


xs = rand((A(), B(), C(), D()), 10000);
display(@benchmark foo!($xs);)

end
```

</details>

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  267.399 μs …   3.118 ms  ┊ GC (min … max):  0.00% … 90.36%
 Time  (median):     278.904 μs               ┊ GC (median):     0.00%
 Time  (mean ± σ):   316.971 μs ± 306.290 μs  ┊ GC (mean ± σ):  11.68% ± 10.74%

  █                                                             ▁
  █▆▄▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▇▇ █
  267 μs        Histogram: log(frequency) by time       2.77 ms <

 Memory estimate: 654.75 KiB, allocs estimate: 21952.
```

SumTypes.jl

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

A(;common_field=1, a=true, b=10) = A(common_field, a, b) 
B(;common_field=1, a=1, b=1.0, d=1 + 1.0im) = B(common_field, a, b, d)
C(;common_field=1, b=2.0, d=false, e=3.0, k=Complex{Real}(1 + 2im)) = C(common_field, b, d, e, k)
D(;common_field=1, b=:hi) = D(common_field, b)

foo!(xs) = for i in eachindex(xs)
    xs[i] = @cases xs[i] begin
        A => B()
        B => C()
        C => D()
        D => A()
    end
end

xs = rand((A(), B(), C(), D()), 10000);
display(@benchmark foo!($xs);)

end 
```

</details>

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  52.680 μs …  72.570 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     53.590 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   53.718 μs ± 756.064 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

        ▁▂▁▃▆▅█▇▅▅▃▁▁                                           
  ▁▂▂▃▅▆██████████████▇▇▅▄▄▃▂▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  52.7 μs         Histogram: frequency by time         56.7 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

And Unityper.jl:

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
        b::Any = :hi # not isbits
    end
end

foo!(xs) = for i in eachindex(xs)
    @inbounds x = xs[i]
    @inbounds xs[i] = @compactified x::AT begin
        A => B()
        B => C()
        C => D()
        D => A()
    end
end

xs = rand((A(), B(), C(), D()), 10000);
display(@benchmark foo!($xs);)

end
```

</details>

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  54.220 μs …  76.000 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     55.030 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   55.073 μs ± 466.103 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

              ▁▁▅▄▄▅▅█▄▅▃▃▂                                     
  ▁▁▁▁▂▂▂▃▄▆▆███████████████▇▆▅▆▃▃▃▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  54.2 μs         Histogram: frequency by time         56.7 μs <
 Memory estimate: 0 bytes, allocs estimate: 0.
```

SumTypes.jl and Unityper.jl are about equal in this benchmark, though there are cases where there are differences.
SumTypes.jl has some other advantages relative to Unityper.jl such as:
- SumTypes.jl allows [parametric types](https://docs.julialang.org/en/v1/manual/types/#Parametric-Types) for much greater container flexibility.
- SumTypes.jl does not require default values for every field of the struct.
- SumTypes.jl's `@cases` macro is more powerful and flexible than Unityper's `@compactified`.
- SumTypes.jl allows you to hide its variants from the namespace (opt in).

One advantage of Unityper.jl is:
- Because Unityper.jl doesn't allow parameterized types and needs to know all type information at macroexpansion time, their structs have a fixed layout for boxed variables that lets them avoid an allocation when storing heap allocated objects (this allocation would be in addition to the heap allocation for the object itself). If we had used `D(;common_field=1, b="hi")` in our benchmarks, SumTypes.jl could have incurred an allocation whereas Unityper.jl would not. As far as I know, this would requre https://github.com/JuliaLang/julia/issues/8472 in order to avoid in SumTypes.jl
