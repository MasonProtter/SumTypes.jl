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

@test 2 == begin
    @match Left{Int, Int}(1) begin
        Either(Left(x)) => x + 1
    end
end

@test 0 == begin
    @match Right{Int, Int}(1) begin
        Either(Left(x)) => x + 1
        Either(Right(x)) => x - 1
    end
end



