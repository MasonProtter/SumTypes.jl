
macro sum_type(T, blk, _hide_variants=:(hide_variants = false))
    if _hide_variants isa Expr && _hide_variants.head == :(=) && _hide_variants.args[1] == :hide_variants
        hide_variants = _hide_variants.args[2]
    else
        error(ArgumentError("Invalid option $_hide_variants\nThe only current allowed option is hide_variants=true or hide_variants=false`"))
    end
    
    @assert blk isa Expr && blk.head == :block
    T_name, T_params, T_params_constrained = if T isa Symbol
        T, [], []
    elseif T isa Expr && T.head == :curly
        T.args[1], (x -> x isa Expr && x.head == :(<:) ? x.args[1] : x).(T.args[2:end]), T.args[2:end]
    end
    T_nameparam = isempty(T_params) ? T : :($T_name{$(T_params...)})
    filter!(x -> !(x isa LineNumberNode), blk.args)
    
    constructors = generate_constructor_data(T_name, T_params, T_params_constrained, T_nameparam, hide_variants, hash(__module__), blk)
    
    if !allunique(map(x -> x.name, constructors))
        error("constructors must have unique names, got $(map(x -> x.name, constructors))")
    end

    con_expr = generate_constructor_exprs(T_name, T_params, T_params_constrained, T_nameparam, constructors)
    out = generate_sum_struct_expr(T, T_name, T_params, T_params_constrained, T_nameparam, constructors)
    Expr(:toplevel, out, con_expr) |> esc
    # push!(out.args, ex)
    # push!(out.args, values)
    # push!(out.args, converts...) # Conversion statements requre T to be defined
    # esc(out)
end

#------------------------------------------------------

function generate_constructor_data(T_name, T_params, T_params_constrained, T_nameparam, hide_variants, hsh, blk::Expr)
    constructors = []
    for con_ ∈ blk.args
        con_ isa LineNumberNode && continue
        if con_ isa Symbol
            if hide_variants
                gname = Symbol("#", T_name, "#", con_)
            else
                gname = con_
            end
            name = con_
            nt = (;
                  name = name,
                  gname = gname,
                  params = [],
                  store_type = Variant{(), Tuple{}},
                  store_type_uninit = Variant{(), Tuple{}},
                  outer_type = name,
                  gouter_type = gname,
                  field_names = [],
                  field_types = [],
                  params_uninit=[Uninit for _ ∈ T_params],
                  params_constrained = [],
                  value = true,
                  )
            push!(constructors, nt)
        else
            con::Expr = con_
            if con.head != :call
                error("Malformed variant $con_")
            end
            con_name = con.args[1] isa Expr && con.args[1].head == :curly ? con.args[1].args[1] : con.args[1]
            con_params = (con.args[1] isa Expr && con.args[1].head == :curly) ? con.args[1].args[2:end] : []
            if !issubset(con_params, T_params)
                error("constructor parameters ($con_params) for $con_name, not a subset of sum type parameters $T_params")
            end
            #@assert con_params == T_params "constructors currently must have same parameters as the sum type. Got $T and $(con.args[1])"
            con_params_uninit = let v = copy(con_params)
                for i ∈ eachindex(T_params)
                    if T_params[i] ∉ con_params
                        insert!(v, i, Uninit)
                    end
                end
                v
            end
            con_params_constrained = [T_params_constrained[i] for i ∈ eachindex(con_params_uninit) if con_params_uninit[i] != Uninit]
            con_nameparam = isempty(con_params) ? con_name : :($con_name{$(con_params...)})
            con_field_names = map(enumerate(con.args[2:end])) do (i, field)
                @assert field isa Symbol || (field isa Expr && field.head == :(::)) "malformed constructor field $field"
                if field isa Symbol
                    field
                elseif  length(field.args) == 1
                    Symbol(:_, i)
                elseif length(field.args) == 2
                    field.args[1]
                end
            end
            con_field_types = map(con.args[2:end]) do field
                @assert field isa Symbol || (field isa Expr && field.head == :(::)) "malformed constructor field $field"
                if field isa Symbol
                    Any
                elseif  length(field.args) == 1
                    field.args[1]
                elseif length(field.args) == 2
                    field.args[2]
                end
            end
            con_field_types_uninit = map(con_field_types) do T
                T ∈ con_params ? Uninit : T
            end
            
            if hide_variants
                gname = Symbol("#", T_name, "#", con_name)
                gnameparam = isempty(con_params) ? gname : :($gname{$(con_params...)})
            else
                gname = con_name
                gnameparam = con_nameparam
            end

            nt = (;
                  name = con_name,
                  gname = gname,
                  params = con_params,
                  store_type = :($Variant{($(QuoteNode.(con_field_names)...),), Tuple{$(con_field_types...)}}),
                  store_type_uninit = :($Variant{($(QuoteNode.(con_field_names)...),), Tuple{$(con_field_types_uninit...)}}),
                  outer_type = con_nameparam,
                  gouter_type = gnameparam,
                  field_names = con_field_names,
                  field_types = con_field_types,
                  params_uninit= con_params_uninit,
                  params_constrained = con_params_constrained,
                  value = false,
                  )
            push!(constructors, nt)
        end
    end
    constructors
end

#------------------------------------------------------

function generate_constructor_exprs(T_name, T_params, T_params_constrained, T_nameparam, constructors)
    out = Expr(:toplevel)
    #converts = []
    foreach(constructors) do nt#(name, params, nameparam, field_names, types, params_uninit, params_constrained, value, gname, gnameparam)
        name = nt.name
        gname = nt.gname 
        params = nt.params
        store_type = nt.store_type
        store_type_uninit = nt.store_type_uninit
        outer_type = nt.outer_type
        gouter_type = nt.gouter_type
        field_names = nt.field_names
        field_types = nt.field_types
        params_uninit= nt.params_uninit
        params_constrained = nt.params_constrained
        value = nt.value

        outer_type_constrained = isempty(params) ? name : :($name{$(params_constrained...)})
        gouter_type_constrained = isempty(params) ? gname : :($gname{$(params_constrained...)})

        T_uninit = isempty(T_params) ? T_name : :($T_name{$(params_uninit...)})
        T_init = isempty(T_params) ? T_name : :($T_name{$(T_params...)})
        if value
            T_con_fields = map(constructors) do nt
                if nt.value
                    :($(nt.store_type_uninit)($unsafe))
                else
                    nothing
                end
            end
            ex = quote
                const $gname = $(Expr(:new, T_uninit, T_con_fields..., Expr(:call, symbol_to_flag, T_name, QuoteNode(name)) ))
            end

            push!(out.args, ex)
            #push!(values.args, ex)
        else
            field_names_typed = map(((name, type),) -> :($name :: $type), zip(field_names, field_types))
            
            T_con_fields = map(constructors) do nt#(_name, _, _nameparam, _, _, _, _, value, _gname, _gnameparam)
                
                default = nt.value ? :($(nt.store_type_uninit)($unsafe)) : nothing
                name == nt.name ? :($store_type(($(field_names...),))) : default
            end
            T_con = :($gouter_type($(field_names_typed...)) where {$(params_constrained...)} =
                $(Expr(:new, T_uninit, T_con_fields..., Expr(:call, symbol_to_flag, T_name, QuoteNode(name)) ) ))

            T_con_fields2 = map(constructors) do nt
                default = nt.value ? :($(nt.store_type_uninit)($unsafe)) : nothing
                s = Expr(:call, store_type, Expr(:tuple, [:($convert($field_type, $field_name)) for (field_type, field_name) ∈ zip(field_types, field_names)]...))
                nt.name == name ? s : default
            end
            T_con2 = :($gouter_type($(field_names...)) where {$(params_constrained...)} =
                $(Expr(:new, T_uninit, T_con_fields2..., Expr(:call, symbol_to_flag, T_name, QuoteNode(name)) )))
            
            maybe_no_param = if !isempty(params)
                :($gname($(field_names_typed...)) where {$(params...)} = $gouter_type($(field_names...)))
            end
            struct_def = Expr(:struct, false, gouter_type_constrained, Expr(:block, :(1 + 1)))
            # @eval $struct_def
            # dump(struct_def)
            # ex = Expr(:toplevel, struct_def)
            ex = quote
                $struct_def
                $T_con
                $T_con2
                $maybe_no_param
                $SumTypes.parent(::Type{<:$gname}) = $T_name
            end
            push!(out.args, ex)
        end
        enumerate_constructors = collect(enumerate(constructors))
        if_nest = mapfoldr(((cond, data), old) -> Expr(:if, cond, data, old), enumerate_constructors, init=:(error("invalid tag"))) do (i , nt)
            name = nt.name
            data =  map(constructors) do nt
                default = nt.value ? :($(nt.store_type_uninit)($unsafe)) : nothing
                nt.name == name ? :($getfield(x, $(QuoteNode(name))) :: $(nt.store_type)) : default
            end
            :(tag == $i), Expr(:new, T_init, data..., :tag)
        end
        if true#!isempty(T_params)
            push!(out.args,
                  :($Base.convert(::Type{$T_init}, x::$T_uninit) where {$(T_params...)} = $(Expr(:block,
                                                                                                 :(tag = getfield(x, $(QuoteNode(tag)) )),
                                                                                                 if_nest ))))
            push!(out.args, :($T_init(x::$T_uninit) where {$(T_params...)} = $convert($T_init, x)))
        end
    end
    out
end



#------------------------------------------------------

function generate_sum_struct_expr(T, T_name, T_params, T_params_constrained, T_nameparam, constructors)

    # name = nt.name
    # gname = nt.gname 
    # params = nt.params
    # store_type = nt.store_type
    # outer_type = nt.outer_type
    # gouter_type = nt.gouter_type
    # field_names = nt.field_names
    # field_types = nt.field_types
    # params_uninit= nt.params_uninit
    # params_constrained = nt.params_constrained
    # value = nt.value
    
    con_outer_types  = (x -> x.outer_type ).(constructors)
    con_gouter_types = (x -> x.gouter_type).(constructors)
    con_names        = (x -> x.name       ).(constructors)
    con_gnames       = (x -> x.gname      ).(constructors)

    flagtype = length(constructors) <= typemax(UInt8) ? UInt8 : length(constructors) < typemax(UInt16) ? UInt16 : length(constructors) <= typemax(UInt32) ? UInt32 :
        error("Too many variants in SumType, got $(length(constructors)). The current maximum number is $(typemax(UInt32) |> Int)")
    
    data_fields = map(constructors) do nt
        name = nt.name
        store_type = nt.store_type
        if nt.value
            :($name :: $store_type)
        else 
            :($name :: Union{$Nothing, $store_type})
        end
    end
    
    sum_struct_def = Expr(:struct, false, T, Expr(:block, data_fields..., :($tag :: $flagtype), :(1 + 1)))
    enumerate_constructors = collect(enumerate(constructors))
    if_nest_unwrap = mapfoldr(((cond, data), old) -> Expr(:if, cond, data, old),  enumerate_constructors, init=:(error("invalid tag"))) do (i, nt)
        :(tag == $i), :($getfield(x, $(QuoteNode(nt.name)))) 
    end

    ex = quote
        $sum_struct_def
        $SumTypes.is_sumtype(::Type{<:$T_name}) = true
        
        $SumTypes.flagtype(::Type{<:$T_name}) = $flagtype
        
        $SumTypes.symbol_to_flag(::Type{<:$T_name}, sym::Symbol) =
            $(foldr(collect(enumerate(con_names)), init=:(error("Invalid tag symbol $sym"))) do (i, _sym), old
                  Expr(:if, :(sym == $(QuoteNode(_sym))), flagtype(i), old)
              end)
        $SumTypes.flag_to_symbol(::Type{<:$T_name}, flag::$flagtype) =
            $(foldr(collect(enumerate(con_names)), init=:(error("Invalid tag symbol $sym"))) do (i, sym), old
                  Expr(:if, :(flag == $i), QuoteNode(sym), old)
              end)
        $SumTypes.tags_flags_nt(::Type{<:$T_name}) = $(Expr(:tuple, Expr(:parameters, (Expr(:kw, name, flagtype(i)) for (i, name) ∈ enumerate(con_names))...)))
        $SumTypes.tags(::Type{<:$T_name}) = $(Expr(:tuple, map(x -> QuoteNode(x.name), constructors)...))
        
        $SumTypes.constructors(::Type{$T_name}) =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.store_type_uninit for nt ∈ constructors)...)))
        $SumTypes.constructors(::Type{$T_nameparam}) where {$(T_params...)} =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.store_type for nt ∈ constructors)...)))
        
        $SumTypes.unwrap(x::$T_nameparam) where {$(T_params...)}= let tag = $get_tag(x)
            $if_nest_unwrap
        end
        $Base.adjoint(::Type{$T_name}) =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.gname  for nt ∈ constructors)...)))
        
        $Base.adjoint(::Type{$T_nameparam}) where {$(T_params...)} =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.value ? :($T_nameparam($(nt.gname))) : nt.gouter_type for nt ∈ constructors)...)))
        $Base.show(io::IO, x::$T_name) = $show_sumtype(io, x)
        $Base.show(io::IO, m::MIME"text/plain", x::$T_name) = $show_sumtype(io, m, x)

        Base.:(==)(x::$T_name, y::$T_name) = ($get_tag(x) == $get_tag(y)) && ($unwrap(x) == $unwrap(y))
    end
    foreach(constructors) do nt
        cons = quote
            $SumTypes.constructor(::Type{$T_name}, ::Type{Val{$(QuoteNode(nt.name))}}) = $(nt.store_type_uninit)
            $SumTypes.constructor(::Type{$T_nameparam}, ::Type{Val{$(QuoteNode(nt.name))}}) where {$(T_params...)} = $(nt.store_type)
        end
        push!(ex.args, cons)
    end
    ex
end
