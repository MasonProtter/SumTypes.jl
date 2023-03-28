# SumTypes.jl

A julian implementation of sum types. Sum types, sometimes called 'tagged unions' are the type system equivalent 
of the [disjoint union](https://en.wikipedia.org/wiki/Disjoint_union) operation (which is *not* a union in the 
traditional sense). From a category theory perspective, sum types are interesting because they are *dual* to 
`Tuple`s (whatever that means). In the 
[Rust programming language](https://doc.rust-lang.org/book/ch06-00-enums.html), these are called "Enums".

At the end of the day, a sum type is really just a fancy word for a container that can store data of a few 
different, pre-declared types and is labelled by how it was instantiated.

Users of statically typed programming languages often prefer Sum types to unions because it makes type checking 
easier. In a dynamic language like julia, the benefit of these objects is less obvious, but there are cases where
they're helpful.

A common use-case for sum types is as a richer version of eums (enum in the 
[julia sense](https://docs.julialang.org/en/v1/base/base/#Base.Enums.@enum), not in the Rust sense):
```julia
julia> @sum_type Fruit begin
           Apple
           Banana
           Orange
       end

julia> Apple
Apple::Fruit

julia> Banana
Banana::Fruit

julia> Orange
Orange::Fruit

julia> typeof(Apple) == typeof(Banana) == typeof(Orange) == Fruit
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
[type stabe](https://docs.julialang.org/en/v1/manual/performance-tips/#Write-%22type-stable%22-functions)!

``` julia
julia> Base.return_types(foo, Tuple{})
1-element Vector{Any}:
 Either{Int64, Float64}
 
julia> isconcretetype(Either{Int, Float64})
true
```
Note that unlike `Union{A, B}`, `A <: Either{A,B}` is false, and `Either{A, A}` is distinct from `A`.

## Pattern matching on Sum types

Okay, that's nice but how do I actually access the data enclosed in a `Fruit` or an `Either`? The answer is pattern matching. 
SumTypes.jl exposes a `@cases` macro for efficiently unwrapping and branching on the contents of a sum type:

```julia
julia> myfruit = Orange
Orange::Fruit

julia> @cases myfruit begin
           Apple => "Got an apple!"
           Orange => "Got an orange!"
           Banana => throw(error("I'm allergic to bananas!"))
       end
"Got an orange!"

julia> @cases Banana begin
           Apple => "Got an apple!"
           Orange => "Got an orange!"
           Banana => throw(error("I'm allergic to bananas!"))
       end
ERROR: I'm allergic to bananas!
[...]
``` 
`@cases` can automatically detect if you did't give an exhaustive set of cases (with no runtime penalty) and throw an error.
```julia
julia> @cases myfruit begin
           Apple() => "Got an apple!"
           Orange() => "Got an orange!"
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

## Performance

In the same way as [Unityper.jl](https://github.com/YingboMa/Unityper.jl) is able to provide a dramatic speedup versus manual union splitting, SumTypes.jl can do this too:

### Branching on abstractly typed data
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
 Range (min … max):  393.061 μs …   6.725 ms  ┊ GC (min … max): 0.00% … 90.92%
 Time  (median):     434.257 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   483.461 μs ± 435.758 μs  ┊ GC (mean ± σ):  9.38% ±  9.39%

  █▅▃▁                                                          ▁
  █████▆▆▃▃▁▁▃▁▁▁▁▁▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▄▃▅ █
  393 μs        Histogram: log(frequency) by time        4.2 ms <

 Memory estimate: 654.16 KiB, allocs estimate: 21950.
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

a(;common=1, a=true, b=10) = A(common, a, b) 
b(;common=1, a=1, b=1.0, d=1 + 1.0im) = B(common, a, b, d)
c(;common=1, b=2.0, d=false, e=3.0, k=Complex{Real}(1 + 2im)) = C(common, b, d, e, k)
d(;common=1, b=:hi) = D(common, b)

foo!(xs) = for i in eachindex(xs)
    xs[i] = @cases xs[i] begin
        A => b()
        B => c()
        C => d()
        D => a()
    end
end

xs = rand((a(), b(), c(), d()), 10000);
display(@benchmark foo!($xs);)

end 
```
</details>
```
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  83.951 μs … 262.854 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     86.286 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   89.819 μs ±  12.281 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▆█▆▆▃▂▄▃▄▁                                                   ▁
  ██████████▆▅▆▇▇▅▇▇▇▆▅▇▆▃▇▆▇▆▅▇▆▅▅▇▅▅▅▄▄▄▅▄▄▄▅▅▄▄▅▄▄▃▃▄▄▄▄▅▄▅ █
  84 μs         Histogram: log(frequency) by time       157 μs <

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
 Range (min … max):  69.355 μs … 234.343 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     75.388 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   77.753 μs ±  13.757 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  █▃▄▃▇▆▆▃▄      ▁                                             ▂
  ██████████▇▇█▇▇█████▆▆▆▆▆▆▇▆▅▇▆▆▅▄▆▇▆▆▆▅▇▆▅▆▅▄▅▄▄▅▄▆▅▅▅▅▅▅▅▅ █
  69.4 μs       Histogram: log(frequency) by time       149 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

We can see that Unityper.jl is able to beat SumTypes.jl in this benchmark, but it's fairly close. 

In exchange for this modest performance loss, SumTypes.jl has some advantages relative to Unityper.jl too, such as 
- SumTypes.jl allows [parametric types](https://docs.julialang.org/en/v1/manual/types/#Parametric-Types) for much greater container flexibility (Unityper does some memory layout optimizations that won't work with parametric types). 
- SumTypes.jl does not require default values for every field of the struct
- SumTypes.jl's `@cases` macro is more powerful and flexible than Unityper's `@compactified`.
