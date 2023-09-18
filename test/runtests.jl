using Test, SumTypes


@sum_type Foo begin
    Bar(::Int)
    Baz(x)
end

@sum_type Either{A, B} begin
    Left{A}(::A)
    Right{B}(::B)
end

@sum_type Result{T <: Union{Number, Uninit}} begin
    Failure
    Success{T}(::T)
end

function log_nothrow(x::T)::Result{T} where{T<:AbstractFloat}
  if x < zero(x) 
      return Failure
  end
  Success(log(x))
end

Base.getproperty(f::Foo, s::Symbol) = error("Don't do that!")
Base.getproperty(f::Either, s::Symbol) = error("Don't do that!")
Base.getproperty(f::Result, s::Symbol) = error("Don't do that!")

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

    @test log_nothrow(1.0) == Success(0.0)
    @test log_nothrow(-1.0) == Failure

    @test_throws Exception macroexpand(@__MODULE__(),
                                       :(@cases x begin
                                             Left{Int}(x) => x
                                             Right(x) => x
                                         end))

    @test_throws Exception macroexpand(@__MODULE__(),
                                       :(@cases x begin
                                             [Left, (Right + 1)](x) => x
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
    @test SumTypes.get_tag(Left([1])) == :Left

    @test convert(Either{Int, Int}, Left(1))  == Left(1)
    @test convert(Either{Int, Int}, Left(1)) !== Left(1)
    @test convert(Either{Int, Int}, Left(1)) === Either{Int, Int}'.Left(1)
    @test Either{Int, Int}(Left(1)) isa Either{Int, Int}
    
    @test_throws MethodError Left{Int}("hi")
    @test_throws MethodError Right{String}(1)
    @test Left{Int}(0x01) === Left{Int}(1)

    let x = Left(1.0)
        @test SumTypes.isvariant(x, :Left) == true
        @test SumTypes.isvariant(x, :Right) == false
        @test SumTypes.unwrap(x)[1] == 1.0
    end
end

#--------------------------------------------------------

@sum_type List{A} begin 
    Nil
    Cons{A}(::A, ::List) 
end
Cons(x::A, y::List{Uninit}) where {A} = Cons(x, List{A}(y))
Base.getproperty(f::List, s::Symbol) = error("Don't do that!")

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
    B(common_field::Int, a::Int, b::Float64, d::Complex{Float64})
    C(common_field::Int, b::Float64, d::Bool, e::Float64, k::Complex{Float64})
    D(common_field::Int, b::Char)
end
Base.getproperty(f::AT, s::Symbol) = error("Don't do that!")

A(;common=1, a=true, b=10) = A(common, a, b) 
B(;common=1, a=1, b=1.0, d=1 + 1.0im) = B(common, a, b, d)
C(;common=1, b=2.0, d=false, e=3.0, k=1 + 2im) = C(common, b, d, e, k)
D(;common=1, b='h') = D(common, b)

foo!(xs) = for i in eachindex(xs)
    xs[i] = @cases xs[i] begin
        A => B()
        B => C()
        C => D()
        D => A()
    end
end
#CI Doesn't like this test so just disable it in CI
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

#---------------
# https://github.com/MasonProtter/SumTypes.jl/issues/38
struct Singleton end
@testset "Constrained type parameters" begin
    @sum_type FooWrapper{T<:Singleton} begin
        FooWrapper1{T}(::T)
        FooWrapper2{T}(::T)
        FooWrapper3{T}(::T)
    end
    @test FooWrapper2(Singleton()) isa FooWrapper{Singleton}
end

#---------------

module CollectionOfVaraints

using SumTypes, Test

@sum_type Foo begin
    A(::Int, ::Int)
    B(::Float64, ::Float64)
    C(::String)
    D(::Pair{Symbol, Int})
end

foo(x::Foo) = @cases x begin
    [A, B](x, y) => x + y
    C(s)         => parse(Int, s)
    D((_, x))    => x
end

@sum_type Re begin
    Empty
    Class(::UInt8)
    Rep(::Re)
    Alt(::Re, ::Re)
    Cat(::Re, ::Re)
    Diff(::Re, ::Re)
    And(::Re, ::Re)
end;

count_classes(r::Re, c=0) = @cases r begin
    Empty => c
    Class => c + 1
    Rep(x) => c + count_classes(x)
    [Alt, Cat, Diff, And](x, y)  => c + count_classes(x) + count_classes(y)
end;
  
@testset "Collection of variants" begin
    @test foo(A(1, 1)) == 2
    @test foo(B(1, 1.5)) == 2.5
    @test foo(C("3")) == 3
    @test foo(D(:a => 4)) == 4

    @test count_classes(And(Alt(Rep(Class(0x1)), And(Class(0x1), Empty)), Class(0x0))) == 3
end

end

module ModuleScopedSumTypes 

using SumTypes, Test 

@sum_type Foo begin
    A1(::String)
    B(::Float64)
    C1(::String)
    D(::Pair{Symbol, Int})
end

foo(x::Foo) = @cases x begin
    [A1, B](x) => x
    C1(s)         => parse(Int, s)
    D((_, x))    => x
end

@testset "Module scoped sum types" begin
    @test foo(A1("abc")) == "abc"
    @test foo(B(1.5)) == 1.5
    @test foo(C1("3")) == 3
    @test foo(D(:a => 4)) == 4
end
end