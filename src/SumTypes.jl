module SumTypes

export @sum_type, @cases, Uninit, full_type

using MacroTools: MacroTools

function constructors end
function constructor end
function variants_Tuple end
function unwrap end
is_sumtype(::Type{T}) where {T}   = false

function get_tag end
function tags end

isexpr(x, head) = x isa Expr && x.head == head

"""
    isvariant(x::SumType, s::Symbol)

For an `x` which was created as a `@sum_type`, check if it's variant tag is `s`. e.g.

    @sum_type Either{L, R} begin
        Left{L}(::L)
        Right{R}(::R)
    end

    let x::Either{Int, Int} = Left(1)
        isvariant(x, :Left)  # true
        isvariant(x, :Right) # false
    end
"""
function isvariant end

struct Unsafe end
const unsafe = Unsafe()

struct Uninit end

struct Variant{name, fieldnames, Tup <: Tuple}
    data::Tup
    Variant{name, fieldnames, Tup}(::Unsafe) where {name, fieldnames, Tup} = new{name, fieldnames, Tup}()
    Variant{name, fieldnames, Tup}(t::Tuple) where {name, fieldnames, Tup <: Tuple} = new{name, fieldnames, Tup}(t)
end
get_name(::Variant{name}) where {name} = name
Base.:(==)(v1::Variant{name}, v2::Variant{name}) where {name} = v1.data == v2.data

Base.iterate(x::Variant, s = 1) = iterate(x.data, s)
Base.indexed_iterate(x::Variant, i::Int, state=1) = (Base.@_inline_meta; (getfield(x.data, i), i+1))
Base.getindex(x::Variant, i) = x.data[i]

show_sumtype(io::IO, m::MIME, x) = show_sumtype(io, x)
function show_sumtype(io::IO, x::T) where {T}
    data = unwrap(x)
    sym = get_name(data)
    if length(data.data) == 0
        print(io, String(sym), "::", T)
    else
        print(io, String(sym), '(', join((repr(field) for field ∈ data), ", "), ")::", T)
    end
end

struct Converter{T, U} end
(::Converter{T, U})(x) where {T, U} = convert(T, U(x))
Base.show(io::IO, x::Converter{T, U}) where {T, U} = print(io, "$T'.$U")

include("sum_type.jl") # @sum_type defined here
include("cases.jl")    # @cases    defined here
include("precompile.jl")

end # module
