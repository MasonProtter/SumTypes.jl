# SumTypes.jl

A julian implementation of sum types. Sum types, sometimes called
'tagged unions' are the type system equivalent of the [disjoint
union](https://en.wikipedia.org/wiki/Disjoint_union) operation (which
is *not* a union in the traditional sense). In a category theory
perspective, sum types are interesting because they are *dual* to
`Tuple`s.

Users of statically typed programming langauges often prefer Sum types
to unions because it makes type checking easier. In a dynamic langauge
like julia, the benefit of these objects is less obvious, but perhaps
someone can find a fun usecase.

Let's explore a very fundamental sum type (fundamental in the sense
that all other sum types may be derived from it):

```julia
julia> @sum_type Either{A, B} begin
           Left{A, B}(::A)
           Right{A, B}(::B)
       end
```

This says that we have a sum type `Either{A, B}`, and it can hold a
value that is either of type `A` or of type `B`. `Either` has two
'constructors' which we have called `Left{A,B}` and
`Right{A,B}`. These exist essentially as a way to have instances of
`Either` carry a record of how they were constructed by being wrapped
in dummy structs named `Left` or `Right`. Here we construct some
instances of `Either`:

```julia
julia> Left{Int, Int}(1)
Either{Int64,Int64}(Left{Int64,Int64}(1))

julia> Right{Int, Float64}(1.0)
Either{Int64,Float64}(Right{Int64,Float64}(1.0))
```

Note that unlike `Union{A, B}`, `A <: Either{A,B}` is false, and
`Either{A, A}` is distinct from `A`.


Here's a recursive list sum type:

```julia 
julia> @sum_type List{A} begin 
	Nil{A}()
	Cons{A}(::A, ::List{A}) 
end

julia> Nil{Int}()
List{Int64}(Nil{Int64}())

julia> Cons{Int}(1, Cons{Int}(1, Nil{Int}()))
List{Int64}(Cons{Int64}(1, List{Int64}(Cons{Int64}(1, List{Int64}(Nil{Int64}())))))
```


You can also use sum types to define a type level enum:
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
```

## Pattern matching on Sum types

Because of the structure of sum types, they lend themselves naturally
to things like pattern matching. As such, `SumTypes.jl` re-exports
`MLStyle.@match` from MLStyle.jl and automatically declares Sum types
as MLStyle record types so they can be destructured:

```julia
julia> @match Left{Int, Int}(1) begin
           Either(Left(x)) => x + 1
       end
2

julia> @match Right{Int, Int}(1) begin
           Either(Left(x)) => x + 1
           Either(Right(x)) => x - 1
       end
0
```
