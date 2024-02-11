
using PrecompileTools

@setup_workload begin
    @compile_workload begin
    	blk = :(begin 
    				Bar(::Int) 
    				Baz(x) 
    			end)
        _sum_type(:(Foo <: AbstractFoo), QuoteNode(:visible), blk)
        blk = :(begin
           			B{X}(a::X)
          			C{X}(b::X)
       			end)
        _sum_type(:(A{X<:Union{Real, SumTypes.Uninit}}), QuoteNode(:visible), blk)
        blk = :(begin
				    A(common_field::Int, a::Bool, b::Int)
				    B(common_field::Int, a::Int, b::Float64, d::Complex{Float64})
				    C(common_field::Int, b::Float64, d::Bool, e::Float64, k::Complex{Float64})
				    D(common_field::Int, b::Char)
    			end)
    	_sum_type(:(AT), QuoteNode(:visible), blk)
    	blk = :(begin
    				Left{A}(::A)
    				Right{B}(::B)
				end)
    	_sum_type(:(Either2{A, B}), QuoteNode(:hidden), blk)
    end
end