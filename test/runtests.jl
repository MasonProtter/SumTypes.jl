using Test, SumTypes


@sum_type Foo begin
    Bar(::Int)
    Baz(x)
end

@sum_type Either{A, B} begin
    Left{A}(::A)
    Right{B}(::B)
end

#-------------------
@testset "Basics  " begin
    @test SumTypes.is_sumtype(Int) == false
    @test Bar(1) isa Foo
    @test_throws MethodError Foo(1)

    function either_test(x::Either)
        let x::Either{Int, Int} = x
            @cases x begin
                Left(l) => l + 1
                Right(r) => r - 1
            end
        end
    end
    @test either_test(Left(1)) == 2
    @test either_test(Right(1)) == 0
    
    function either_test_incomplete(x::Either)
        let x::Either{Int, Int} = x
            @cases x begin
                Left(l) => l + 1
            end
        end
    end
    
    @test_throws ErrorException either_test_incomplete(Left(1))

    function either_test_overcomplete(x::Either)
        let x::Either{Int, Int} = x
            @cases x begin
                Left(l) => l + 1
                Right(r) => r - 1
                Some_Bullshit => Inf
            end
        end
    end
    
    @test_throws ErrorException either_test_overcomplete(Left(1))

    @test_throws Exception macroexpand(@__MODULE__(),
                                       :(@cases x begin
                                             Left{Int}(x) => x
                                             Right(x) => x
                                         end))

    @test_throws Exception SumTypes._sum_type(
        :Blah, :(begin
                     duplicate_field
                     duplicate_field
                 end))
    
    @test_throws Exception SumTypes._sum_type(
        :Blah, :some_option, :(begin
                     duplicate_field
                 end))
    
    @test_throws Exception SumTypes._sum_type(
        :Blah, :(begin
                     x * field^2  -1 
                 end))
    
    @test_throws Exception SumTypes._sum_type(
        :(Blah{T}), :(begin
                         foo{U}(::U)
                     end ))
    
    let x = Left([1]), y = Left([1.0]), z = Right([1])
        @test x == y
        @test x != z
    end
    @test SumTypes.get_tag_sym(Left([1])) == :Left

    @test convert(full_type(Either{Int, Int}), Left(1))  == Left(1)
    @test convert(full_type(Either{Int, Int}), Left(1)) !== Left(1)
    @test convert(full_type(Either{Int, Int}), Left(1)) === Either{Int, Int}'.Left(1)
    @test Either{Int, Int, 15, 0}(Left(1)) isa Either{Int, Int, 15, 0}
    @test Either{Int, Int, 15, 0}(Either{Int, Int}(Left(1))) isa Either{Int, Int, 15, 0}
    
    @test_throws MethodError Left{Int}("hi")
    @test_throws MethodError Right{String}(1)
    @test Left{Int}(0x01) === Left{Int}(1)

    @test full_type(Either{Nothing, Nothing}) == Either{Nothing, Nothing, 0, 0}
    @test full_type(Either{Int, Int}) == Either{Int, Int, 15, 0}
    @test full_type(Either{Int, String}) == Either{Int, String, 8, 1}
end

#--------------------------------------------------------



@sum_type List{A} begin 
    Nil
    Cons{A}(::A, ::List) 
end
Cons(x::A, y::List{Uninit}) where {A} = Cons(x, List{A}(y))

List(first, rest...) = Cons(first, List(rest...))
List() = Nil

function Base.Tuple(l::List)
    @cases l begin
        Nil => ()
        Cons(a, b) => (a, Tuple(b)...)
    end 
end
Base.length(l::List) = @cases l begin
    Nil => 0
    Cons(_, l) => 1 + length(l)
end
function Base.collect(l::List{T}) where {T}
    v = Vector{T}(undef, length(l))
    for i ∈ eachindex(v)
        l::List{T} = @cases l begin
            Nil => error()
            Cons(a, rest) => begin
                v[i] = a
                rest
            end
        end
    end
end 

function collect_to!(v, l)
    @cases l begin
        Nil => v
        Cons(a, b) => (push!(v, a); collect_to!(v, b))
    end
end

function Base.show(io::IO, l::List)
    print(io, "List", Tuple(l))
end

@testset "Recursive Sum Types" begin
    @test Nil isa List{Uninit}
    @test Cons(1, Cons(1, Nil)) isa List{Int}
    @test Tuple(List(1, 2, 3, 4, 5)) == (1, 2, 3, 4, 5)
end


#--------------------------------------------------------

@sum_type AT begin
    A(common_field::Int, a::Bool, b::Int)
    B(common_field::Int, a::Int, b::Float64, d::Complex)
    C(common_field::Int, b::Float64, d::Bool, e::Float64, k::Complex{Real})
    D(common_field::Int, b::Any)
end

A(;common=1, a=true, b=10) = A(common, a, b) 
B(;common=1, a=1, b=1.0, d=1 + 1.0im) = B(common, a, b, d)
C(;common=1, b=2.0, d=false, e=3.0, k=Complex{Real}(1 + 2im)) = C(common, b, d, e, k)
D(;common=1, b=:hi) = D(common, b)

foo!(xs) = for i in eachindex(xs)
    xs[i] = @cases xs[i] begin
        A => B()
        B => C()
        C => D()
        D => A()
    end
end


# #CI Doesn't like this test so just uncomment it for local testing
if !haskey(ENV, "CI") || ENV["CI"] != "true"
    @testset "Allocation-free @cases" begin
        xs = map(x->rand((A(), B(), C(), D())), 1:10000);
        foo!(xs)
        @test @allocated(foo!(xs)) == 0
    end
end

#--------------------------------------------------------

@sum_type Hider{T} :hidden begin
    A
    B{T}(::T)
end

@sum_type Hider2 :hidden begin
    A
    B
end 

@testset "hidden variants" begin
    @test Hider{Int}'.A isa Hider{Int}
    @test Hider'.A isa Hider{SumTypes.Uninit}
    @test Hider'.A != A
    @test Hider'.B != B

    @test 1 == @cases Hider'.A begin
        A() => 1
        B(a) => a
    end
    @test 2 == @cases Hider'.B(2) begin
        A() => 1
        B(a) => a
    end

    @test Hider2'.A isa Hider2
    @test Hider2'.B isa Hider2
    @test Hider2'.A != A
    @test Hider2'.B != B

    @test 1 == @cases Hider2'.A begin
        A => 1
        B(a) => a
    end
    @test 2 == @cases Hider2'.B begin
        A => 1
        B => 2
    end

end



@sum_type Either2{A, B} :hidden begin
    Left{A}(::A)
    Right{B}(::B)
end

SumTypes.show_sumtype(io::IO, x::Either2) = @cases x begin
    Left(a) => print(io, "L($a)")
    Right(a) => print(io, "R($a)")
end

SumTypes.show_sumtype(io::IO, ::MIME"text/plain", x::Either2) = @cases x begin
    Left(a) => print(io, "The Leftestmost Value: $a")
    Right(a) => print(io, "The Rightestmost Value: $a")
end

@sum_type Fruit begin
    apple
    banana
    orange
end

@testset "printing  " begin
    @test repr(Left(1)) ∈  ("Left(1)::Either{Int64, Uninit}", "Left(1)::Either{Int64,Uninit}") 
    @test repr("text/plain", Right(3)) ∈ ("Right(3)::Either{Uninit, Int64}", "Right(3)::Either{Uninit,Int64}")

    let Left = Either2'.Left, Right = Either2'.Right
        @test repr("text/plain", Left(1)) == "The Leftestmost Value: 1"
        @test repr(Right(3)) == "R(3)"
    end
    @test repr(apple) == "apple::Fruit"
    @test repr(Either{Int, Int}'.Left) ∈ ("Either{Int64, Int64}'.Left{Int64}", "Either{Int64,Int64}'.Left{Int64}")
end

