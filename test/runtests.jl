using Test, SumTypes

@sum_type Foo begin
    Bar(::Int)
    Baz(::Float64)
end

@test Bar(1) isa Foo
@test_throws MethodError Foo(1)


@sum_type Either{A, B} begin
    Left{A, B}(::A)
    Right{A, B}(::B)
end

let x = Right{Int, Int}(1)
    @case Either f((x,)::Left)  = x + 1
    @case Either f((x,)::Right) = x - 1
    @test f(x) == 0
    @test SumTypes.iscomplete(f, Either)
end

let x = Left{Int, Int}(1)
    @case Either f((x,)::Left)  = x + 1
    @test f(x) == 2
    @test !(SumTypes.iscomplete(f, Either))
end

@test_throws TypeError Left{Int, String}("hi")
@test_throws TypeError Right{Int, String}(1)

@sum_type List{A, L} begin 
    Nil{A, L}()
    Cons{A, L}(::A, ::L) 
end

@test Nil{Int, List}() isa List{Int, List}
@test Cons{Int, List}(1, Cons{Int, List}(1, Nil{Int, List}())) isa List{Int, List}
