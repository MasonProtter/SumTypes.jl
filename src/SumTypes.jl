module SumTypes

export @sum_type, @cases, Uninit

using MacroTools: MacroTools

function parent end
function constructors end
function constructor end 
function constructors_Union end
function unwrap end
function tags end
function deparameterize end
is_sumtype(::Type{T}) where {T}   = false
function flagtype end
function flag_to_symbol end
function symbol_to_flag end
function tags_flags_nt end


struct Unsafe end
const unsafe = Unsafe()

struct Uninit end

struct Singleton{name} end
Base.iterate(x::Singleton, s = 1) = nothing
maybe_type(::Type{x}) where {x} = x
maybe_type(::Singleton{x}) where {x} = Singleton{x}

const tag = Symbol("#tag#")
get_tag(x) =getfield(x, tag)
get_tag_sym(x::T) where {T} = tags_flags_nt(T)[get_tag(x)]
# get_tag(x::T) where {T} = getfield(x, tag)


show_sumtype(io::IO, m::MIME, x) = show_sumtype(io, x)
function show_sumtype(io::IO, x::T) where {T}
    tag = get_tag(x)
    sym = flag_to_symbol(T, tag)
    if getfield(x, sym) isa Singleton
        print(io, String(sym), "::", typeof(x))
    else
        print(io, String(sym), '(', join((repr(data) for data ∈ getfield(x, sym)), ", "), ")::", typeof(x))
    end
end

include("sum_type.jl") # @sum_type defined here
include("cases.jl")    # @cases    defined here

end # module
