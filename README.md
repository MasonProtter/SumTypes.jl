# SumTypes.jl

A julian implementation of sum types. Sum types, sometimes called 'tagged unions' are the type system equivalent 
of the [disjoint union](https://en.wikipedia.org/wiki/Disjoint_union) operation (which is *not* a union in the 
traditional sense). From a category theory perspective, sum types are interesting because they are *dual* to 
`Tuple`s (whatever that means). In the 
[Rust programming language](https://doc.rust-lang.org/book/ch06-00-enums.html), these are called `Enums`.

At the end of the day, a sum type is really just a fancy word for a container that can store data of a few 
different, pre-declared types and is labelled by how it was instantiated.

Users of statically typed programming languages often prefer Sum types to unions because it makes type checking 
easier. In a dynamic language like julia, the benefit of these objects is less obvious, but perhaps someone can 
find a fun use case.

A common use-case for sum types is as a richer version of eums (enum in the 
[julia sense](https://docs.julialang.org/en/v1/base/base/#Base.Enums.@enum), not in the Rust sense):
```julia
julia> @sum_type Fruit begin
           Apple()
           Banana()
           Orange()
       end

julia> Apple()
Fruit(Apple())

julia> Banana()
Fruit(Banana())

julia> Orange()
Fruit(Orange())

julia> typeof(Apple()) == typeof(Banana()) == typeof(Orange()) == Fruit
true
```

But this isn't particularly interesting. More intesting is sum types which can enclose data. 
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
Either{Int64, Uninit}(Left{Int64}(1))

julia> Right(1.0)
Either{Uninit, Float64}(Right{Float64}(1.0))
```
Notice that because both `Left{A}` and `Right{B}` each carry one fewer type parameter than `Either{A,B}`, then simply writing
`Left(1)` is *not enough* to fully specify the type of the full `Either`, so the unspecified field is `SumTypes.Uninit` by default.

In cases like this, you can rely on implicit conversion to get the fully initialized type. E.g.
``` julia
julia> let x::Either{Int, Float64} = Left(1)
           x
       end
Either{Int64, Float64}(Left{Int64}(1))
```
Typically, you'll do this by enforcing a return type on a function:
``` julia
julia> function foo()::Either{Int, Float64}
           # Randomly return either a Left(1) or a Right(2.0)
           rand(Bool) ? Left(1) : Right(2.0)
       end
foo (generic function with 1 method)

julia> foo()
Either{Int64, Float64}(Right{Float64}(2.0))

julia> foo()
Either{Int64, Float64}(Left{Int64}(1))
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
julia> myfruit = Orange()
Fruit(Orange())

julia> @cases myfruit begin
           Apple() => "Got an apple!"
           Orange() => "Got an orange!"
           Banana() => throw(error("I'm allergic to bananas!"))
       end
"Got an orange!"

julia> @cases Banana() begin
           Apple() => "Got an apple!"
           Orange() => "Got an orange!"
           Banana() => throw(error("I'm allergic to bananas!"))
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
ERROR: Inexhaustic @cases specification. Got cases Union{Apple, Orange}, expected Union{Apple, Banana, Orange}
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
