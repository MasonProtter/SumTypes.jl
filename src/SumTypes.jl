module SumTypes

export @sum_type, @cases, Uninit, full_type

using MacroTools: MacroTools

function parent end
function constructors end
function constructor end 
function constructors_Union end
function variants_Tuple end
function unwrap end
function tags end
function deparameterize end
is_sumtype(::Type{T}) where {T}   = false
function flagtype end
function flag_to_symbol end
function symbol_to_flag end
function tags_flags_nt end
function variants_Tuple end
function strip_size_params end
function full_type end

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
isvariant(x::T, s::Symbol) where {T} = get_tag(x) == symbol_to_flag(T, s)

struct Unsafe end
const unsafe = Unsafe()

struct Uninit end

struct Variant{fieldnames, Tup <: Tuple}
    data::Tup
    Variant{fieldnames, Tup}(::Unsafe) where {fieldnames, Tup} = new{fieldnames, Tup}()
    Variant{fieldnames, Tup}(t::Tuple) where {fieldnames, Tup <: Tuple} = new{fieldnames, Tup}(t)
end
Base.:(==)(v1::Variant, v2::Variant) = v1.data == v2.data

Base.iterate(x::Variant, s = 1) = iterate(x.data, s)
Base.indexed_iterate(x::Variant, i::Int, state=1) = (Base.@_inline_meta; (getfield(x.data, i), i+1))
Base.getindex(x::Variant, i) = x.data[i]

const tag = Symbol("#tag#")
get_tag(x) = getfield(x, tag)
get_tag_sym(x::T) where {T} = keys(tags_flags_nt(T))[Int(get_tag(x)) + 1]

show_sumtype(io::IO, m::MIME, x) = show_sumtype(io, x)
function show_sumtype(io::IO, x::T) where {T}
    tag = get_tag(x)
    sym = flag_to_symbol(T, tag)
    T_stripped = T_string_stripped(T)
    if unwrap(x) isa Variant{(), Tuple{}}
        print(io, String(sym), "::", T_stripped)
    else
        print(io, String(sym), '(', join((repr(data) for data ∈ unwrap(x)), ", "), ")::", T_stripped)
    end
end
function T_string_stripped(::Type{_T}) where {_T}
    @assert is_sumtype(_T)
    T = full_type(_T)
    T_stripped = if length(T.parameters) == 3
        String(T.name.name)
    else
        string(String(T.name.name), "{", join(repr.(T.parameters[1:end-3]), ", "), "}")
    end 
end


struct Converter{T, U} end
(::Converter{T, U})(x) where {T, U} = convert(T, U(x))
Base.show(io::IO, x::Converter{T, U}) where {T, U} = print(io, "$(T_string_stripped(T))'.$U")


include("compute_storage.jl")
include("sum_type.jl") # @sum_type defined here
include("cases.jl")    # @cases    defined here


end # module
