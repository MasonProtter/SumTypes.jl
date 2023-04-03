struct PlaceHolder end

macro assume_effects(args...)
    if isdefined(Base, Symbol("@assume_effects"))
        ex = :($Base.@assume_effects($(args...)))
    else
        ex = args[end]
    end
    esc(ex)
end

@assume_effects :consistent :foldable function unsafe_padded_reinterpret(::Type{T}, x::U) where {T, U}
    @assert isbitstype(T) && isbitstype(U)
    n, m = sizeof(T), sizeof(U)
    if sizeof(U) < sizeof(T)
        payload = (x, ntuple(_ -> zero(UInt8), Val(n-m)), )
    else
        payload = x
    end
    let r = Ref(payload)
        GC.@preserve r begin
            p = pointer_from_objref(r)
            unsafe_load(Ptr{T}(p))
        end
    end
end

function extract_info(variants)
    data = map(variants) do variant
        (names, store_types) = variant.parameters
        bits = []
        ptrs = []
        @assert length(names) == length(store_types.parameters)
        foreach(zip(names, store_types.parameters)) do (name, T)
            if isbitstype(T)
                push!(bits, name => T)
            else
                push!(bits, name => SumTypes.PlaceHolder)
                push!(ptrs, name => T)
            end
        end
        bits, ptrs
    end
    bitss = map(x -> x[1], data)
    ptrss = map(x -> x[2], data)
    nptrs = maximum(length, ptrss)
    ptr_names = map(v -> map(x -> x[1], v), ptrss)
    bit_size = maximum(v -> sizeof(Tuple{map(x -> x[2], v)...}), bitss) 
    bit_names = map(v -> map(x -> x[1], v), bitss)
    bit_sigs  = map(v -> map(x -> x[2], v), bitss)
    (;
     bitss = bitss,
     ptrss = ptrss,
     nptrs = nptrs,
     ptr_names = ptr_names,
     bit_size = bit_size,
     bit_names = bit_names,
     bit_sigs  = bit_sigs,
     )
end


make(::Type{ST}, to_make, tag) where {ST} = make(ST, to_make, tag, variants_Tuple(ST))
@generated function make(::Type{ST}, to_make::Var, tag, ::Type{var_Tuple}) where {ST, Var <: Variant, var_Tuple <: Tuple}
    variants = var_Tuple.parameters
    i = findfirst(==(Var), variants)
    nt = extract_info(variants)

    nptrs = nt.nptrs
    ptr_names = nt.ptr_names
    bit_size = nt.bit_size
    bit_names = nt.bit_names
    bit_sigs  = nt.bit_sigs

    bitvariant = :(SumTypes.Variant{($(QuoteNode.(bit_names[i])...),), Tuple{$(bit_sigs[i]...)}}(
        ($(([bit_sigs[i][j] == PlaceHolder ? PlaceHolder() : :(to_make.data[$j]) for j ∈ eachindex(bit_sigs[i])  ])...),) ))
    ptr_args = [:(to_make.data[$j]) for j ∈ eachindex(bit_names[i]) if bit_names[i][j] ∈ ptr_names[i]]
    con = Expr(
        :new,
        ST{bit_size, nptrs},
        :(unsafe_padded_reinterpret(NTuple{$bit_size, UInt8}, $bitvariant)),
        Expr(:tuple, ptr_args..., (nothing for _ ∈ 1:(nptrs-length(ptr_args)))...),
        :tag
    )
end



unwrap(x::ST, var) where {ST} = unwrap(x, var, variants_Tuple(ST))
@generated function unwrap(x::ST, ::Type{Var}, ::Type{var_Tuple}) where {ST, Var, var_Tuple}
    variants = var_Tuple.parameters
    i = findfirst(==(Var), variants)
    nt = extract_info(variants)
    ptrss = nt.ptrss
    nptrs = nt.nptrs
    ptr_names = nt.ptr_names
    bit_size = nt.bit_size
    bit_names = nt.bit_names
    bit_sigs  = nt.bit_sigs
    quote
        names = ($(QuoteNode.(bit_names[i])...),)
        bits = unsafe_padded_reinterpret(Variant{names, Tuple{$(bit_sigs[i]...)}}, x.bits)
        args = $(Expr(:tuple,
                      (bit_names[i][j] ∈ ptr_names[i] ? let k = findfirst(x -> x == bit_names[i][j], ptr_names[i])
                           :(x.ptrs[$k]:: $(ptrss[i][k][2]))
                       end : :(bits.data[$j]) for j ∈ eachindex(bit_names[i]))...))
        Variant{names, $(Var.parameters[2])}(args)
    end
end

Base.@generated function full_type(::Type{ST}, ::Type{var_Tuple}) where {ST, var_Tuple}
    variants = var_Tuple.parameters
    nt = extract_info(variants)
    :($ST{$(nt.bit_size), $(nt.nptrs)})
end
