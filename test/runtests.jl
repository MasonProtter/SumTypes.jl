using Test, SumTypes

@sum_type Foo begin
    Bar(::Int)
    Baz(::Float64)
end

@test Bar(1) isa Foo
@test_throws MethodError Foo(1)


@sum_type Either{A, B} begin
    Left{A}(::A)
    Right{B}(::B)
end

let x::Either{Int, Int} = Right(1)
    @test 0 == @cases x begin
        Left(l)  => l + 1
        Right(r) => r - 1
    end 
end

let x::Either{Int, Int} = Left(1)
    @test_throws ErrorException @cases x begin
        Left(l) => l + 1
    end
end

@test_throws MethodError Left{Int}("hi")
@test_throws MethodError Right{String}(1)
@test_throws MethodError Left{Int}(0x01)

@sum_type List{A, L} begin 
    Nil()
    Cons{A, L}(::A, ::L) 
end
List(first, rest...) = Cons(first, List(rest...))
List() = Nil()

function Base.Tuple(l::List)
    @cases l begin
        Nil() => ()
        Cons(a, b) => (a, Tuple(b)...)
    end 
end 

function Base.show(io::IO, l::List)
    print(io, "List", Tuple(l))
end

@test Nil() isa List{Uninit, Uninit}
@test Cons(1, Cons(1, Nil())) isa List{Int, List{Int, List{Uninit, Uninit}}}
