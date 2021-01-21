# SumTypes.jl

A julian implementation of sum types. Sum types, sometimes called 'tagged unions' are the type system equivalent of the [disjoint union](https://en.wikipedia.org/wiki/Disjoint_union) operation (which is *not* a union in the traditional sense). From a category theory perspective, sum types are interesting because they are *dual* to `Tuple`s (whatever that means).

At the end of the day, a sum type is really just a fancy word for a container that can store data of a few different, pre-declared types and is labelled by how it was instantiated.

Users of statically typed programming languages often prefer Sum types to unions because it makes type checking easier. In a dynamic language like julia, the benefit of these objects is less obvious, but perhaps someone can find a fun use case.

Let's explore a very fundamental sum type (fundamental in the sense that all other sum types may be derived from it):

```julia
julia> using SumTypes

julia> @sum_type Either{A, B} begin
           Left{A, B}(::A)
           Right{A, B}(::B)
       end
```

This says that we have a sum type `Either{A, B}`, and it can hold a value that is either of type `A` or of type `B`. `Either` has two 'constructors' which we have called `Left{A,B}` and `Right{A,B}`. These exist essentially as a way to have instances of
`Either` carry a record of how they were constructed by being wrapped in dummy structs named `Left` or `Right`. Here we construct some instances of `Either`:

```julia
julia> Left{Int, Int}(1)
Either{Int64, Int64}: Left(1)

julia> Right{Int, Float64}(1.0)
Either{Int64, Float64}: Right(1.0)
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
List{Int64}: Nil()

julia> Cons{Int}(1, Cons{Int}(1, Nil{Int}()))
List{Int64}: Cons(1, List{Int64}: Cons(1, List{Int64}: Nil()))
```


You can also use sum types to define a type level enum:
```julia
julia> @sum_type Fruit begin
           Apple()
           Banana()
           Orange()
       end

julia> Apple()
Fruit: Apple()

julia> Banana()
Fruit: Banana()

julia> Orange()
Fruit: Orange()
```

## Pattern matching on Sum types

Because of the structure of sum types, they lend themselves naturally to things like pattern matching. SumTypes.jl exposes a `@case` macro for defining pattern matching cases: 

```julia
@case Either f((x,)::Left)  = x + 1
@case Either f((x,)::Right) = x - 1
 
l = Left{Int, Int}(1)
r = Right{Int, Int}(1)


julia> f(l)
2

julia> f(r)
0
``` 

You can use `SumTypes.iscomplete` to check if all the cases of a sum type are covered:
```julia
@sum_type MyBool begin
    True()
    False()
end
@case MyBool g(::True) = "All good!"

julia> SumTypes.iscomplete(g, MyBool)
false
```

For more advanced mattern matching utilities, consider [MLStyle.jl](https://github.com/thautwarm/MLStyle.jl/).
