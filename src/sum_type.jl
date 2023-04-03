
macro sum_type(T, args...)
    esc(_sum_type(T, args...))
end

_sum_type(T, blk) = _sum_type(T, QuoteNode(:visible), blk)
function _sum_type(T, hidden, blk)
    if hidden == QuoteNode(:hidden)
        hide_variants = true
    elseif hidden == QuoteNode(:visible)
        hide_variants = false
    else
        error(ArgumentError("Invalid option $hidden\nThe only currently allowed option is `:hidden` or `:visible`"))
    end
    
    @assert blk isa Expr && blk.head == :block
    T_name, T_params, T_params_constrained, T_param_bounds = if T isa Symbol
        T, [], [], []
    elseif T isa Expr && T.head == :curly
        T.args[1], (x -> x isa Expr && x.head == :(<:) ? x.args[1] : x).(T.args[2:end]), T.args[2:end], (x -> x isa Expr && x.head == :(<:) ? x.args[2] : Any).(T.args[2:end])
    end
    T_nameparam = isempty(T_params) ? T : :($T_name{$(T_params...)})
    filter!(x -> !(x isa LineNumberNode), blk.args)
    
    constructors = generate_constructor_data(T_name, T_params, T_params_constrained, T_nameparam, hide_variants, blk)
    
    if !allunique(map(x -> x.name, constructors))
        error("constructors must have unique names, got $(map(x -> x.name, constructors))")
    end

    con_expr = generate_constructor_exprs(T_name, T_params, T_params_constrained, T_nameparam, constructors)
    out = generate_sum_struct_expr(T, T_name, T_params, T_params_constrained, T_param_bounds, T_nameparam, constructors)
    Expr(:toplevel, out, con_expr) 
end

#------------------------------------------------------

function generate_constructor_data(T_name, T_params, T_params_constrained, T_nameparam, hide_variants,  blk::Expr)
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
            con.head == :call || throw(ArgumentError("Malformed variant $con_"))
            con_name = con.args[1] isa Expr && con.args[1].head == :curly ? con.args[1].args[1] : con.args[1]
            con_params = (con.args[1] isa Expr && con.args[1].head == :curly) ? con.args[1].args[2:end] : []
            issubset(con_params, T_params) ||
                error("constructor parameters ($con_params) for $con_name, not a subset of sum type parameters $T_params")
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
            unique(con_field_names) == con_field_names || error("constructor field names must be unique, got $(con_field_names) for constructor $con_name")
            
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
    converts = []
    for nt ∈ constructors
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
            ex = quote
                const $gname = $(Expr(:call, make, T_uninit, :($(nt.store_type_uninit)($unsafe)), Expr(:call, symbol_to_flag, T_name, QuoteNode(name)) )) 

            end
            push!(out.args, ex)
        else
            field_names_typed = map(((name, type),) -> :($name :: $type), zip(field_names, field_types))
            T_con = :($gouter_type($(field_names_typed...)) where {$(params_constrained...)} =
                $(Expr(:call, make, T_uninit, :($store_type(($(field_names...),))), Expr(:call, symbol_to_flag, T_name, QuoteNode(name)) )))

            T_con2 = if !all(x -> x ∈ (Any, :Any) ,field_types)
                s = Expr(:call, store_type, Expr(:tuple, [:($convert($field_type, $field_name))
                                                          for (field_type, field_name) ∈ zip(field_types, field_names)]...))
                
                :($gouter_type($(field_names...)) where {$(params_constrained...)} =
                    $(Expr(:call, make, T_uninit, s, Expr(:call, symbol_to_flag, T_name, QuoteNode(name)))))
            end
            maybe_no_param = if !isempty(params)
                :($gname($(field_names_typed...)) where {$(params...)} = $gouter_type($(field_names...)))
            end
            struct_def = Expr(:struct, false, gouter_type_constrained, Expr(:block, :(1 + 1)))
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

        if true
            @gensym N M _tag _T x

            if_nest_conv = mapfoldr(((cond, data), old) -> Expr(:if, cond, data, old),  enumerate_constructors, init=:(error("invalid tag"))) do (i, nt)
                :($_tag == $(i-1) ), :($make($T_init, $unwrap(x, $(nt.store_type)) , $_tag))
            end
            
            push!(converts, T_uninit => quote
                      $Base.convert(::$Type{$_T}, $x::$_T) where {$_T <: $T_name} = $x
                      $Base.convert(::$Type{<:$T_init}, x::$T_uninit) where {$(T_params...)} = let $_tag = $get_tag(x)
                          $if_nest_conv
                      end 
                      (::$Type{<:$T_init})(x::$T_uninit) where {$(T_params...)} = $convert($T_init, x)
                      $Base.convert(::$Type{<:$T_init}, x::$T_uninit{$N, $M}) where {$(T_params...), $N, $M} = let $_tag = $get_tag(x)
                          $if_nest_conv
                      end 
                      (::$Type{<:$_T})(x::$T_name) where {$_T <: $T_name} = $convert($_T, x)
                  end)
        end
    end
    unique!(x -> x[1], converts)
    append!(out.args, map(x -> x[2], converts))
    out
end



#------------------------------------------------------

function generate_sum_struct_expr(T, T_name, T_params, T_params_constrained, T_param_bounds, T_nameparam, constructors)
    con_outer_types  = (x -> x.outer_type ).(constructors)
    con_gouter_types = (x -> x.gouter_type).(constructors)
    con_names        = (x -> x.name       ).(constructors)
    con_gnames       = (x -> x.gname      ).(constructors)

    flagtype =  length(constructors) < typemax(UInt8) ? UInt8 : length(constructors) < typemax(UInt16) ? UInt16 :
        length(constructors) <= typemax(UInt32) ? UInt32 :
        error("Too many variants in SumType, got $(length(constructors)). The current maximum number is $(typemax(UInt32) |> Int)")

    N = Symbol("#N#")
    M = Symbol("#M#")
    T_full = T isa Expr && T.head == :curly ? Expr(:curly, T.args..., N, M) : Expr(:curly, T, N, M)
    sum_struct_def = Expr(:struct, false, T_full,
                          Expr(:block, :(bits :: $NTuple{$N, $UInt8}), :(ptrs :: $NTuple{$M, $Any}), :($tag :: $flagtype), :(1 + 1)))
    enumerate_constructors = collect(enumerate(constructors))
    if_nest_unwrap = mapfoldr(((cond, data), old) -> Expr(:if, cond, data, old),  enumerate_constructors, init=:(error("invalid tag"))) do (i, nt)
        :(tag == $(flagtype(i-1))), :($unwrap(x, $(nt.store_type))) 
    end

    only_define_with_params = if !isempty(T_params)
        @gensym x
        quote
            $SumTypes.constructors(::Type{<:$T_nameparam}) where {$(T_params...)} =
                $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.store_type for nt ∈ constructors)...)))
            $Base.adjoint(::Type{<:$T_nameparam}) where {$(T_params...)} =
                $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.value ? :($T_nameparam($(nt.gname))) : :($Converter{$T_nameparam, $(nt.gouter_type)}()) for nt ∈ constructors)...)))
            $SumTypes.variants_Tuple(::Type{<:$T_nameparam}) where {$(T_params...)} =
                $Tuple{$((nt.store_type for nt ∈ constructors)...)}
            $SumTypes.full_type(::Type{$T_name}) = $full_type($T_name{$(T_param_bounds...)}, $variants_Tuple($T_nameparam{$(T_param_bounds...)}))
        end
    end

    ex = quote
        $sum_struct_def
        $SumTypes.is_sumtype(::Type{<:$T_name}) = true
        $SumTypes.strip_size_params(::Type{$T_name{$(T_params...), $N, $M}}) where {$(T_params...), $N, $M} = $T_nameparam
        $SumTypes.flagtype(::Type{<:$T_name}) = $flagtype
        
        $SumTypes.symbol_to_flag(::Type{<:$T_name}, sym::Symbol) =
            $(foldr(collect(enumerate(con_names)), init=:(error("Invalid tag symbol $sym"))) do (i, _sym), old
                  Expr(:if, :(sym == $(QuoteNode(_sym))), flagtype(i-1), old)
              end)
        $SumTypes.flag_to_symbol(::Type{<:$T_name}, flag::$flagtype) =
            $(foldr(collect(enumerate(con_names)), init=:(error("Invalid tag symbol $sym"))) do (i, sym), old
                  Expr(:if, :(flag == $(i-1)), QuoteNode(sym), old)
              end)
        $SumTypes.tags_flags_nt(::Type{<:$T_name}) = $(Expr(:tuple, Expr(:parameters, (Expr(:kw, name, flagtype(i)) for (i, name) ∈ enumerate(con_names))...)))
        $SumTypes.tags(::Type{<:$T_name}) = $(Expr(:tuple, map(x -> QuoteNode(x.name), constructors)...))
        
        $SumTypes.constructors(::Type{<:$T_name}) =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.store_type_uninit for nt ∈ constructors)...)))
        
        $SumTypes.variants_Tuple(::Type{<:$T_name}) =
            $Tuple{$((nt.store_type_uninit for nt ∈ constructors)...)}
        
        $SumTypes.unwrap(x::$T_nameparam) where {$(T_params...)}= let tag = $get_tag(x)
            $if_nest_unwrap
        end
        $Base.adjoint(::Type{<:$T_name}) =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.gname  for nt ∈ constructors)...)))

        $SumTypes.full_type(::Type{$T_nameparam}) where {$(T_params...)} = $full_type($T_nameparam, $variants_Tuple($T_nameparam))
        
        $Base.show(io::IO, x::$T_name) = $show_sumtype(io, x)
        $Base.show(io::IO, m::MIME"text/plain", x::$T_name) = $show_sumtype(io, m, x)

        Base.:(==)(x::$T_name, y::$T_name) = ($get_tag(x) == $get_tag(y)) && ($unwrap(x) == $unwrap(y))
        $only_define_with_params 
    end
    foreach(constructors) do nt
        con1 = :($SumTypes.constructor(::Type{<:$T_name}, ::Type{Val{$(QuoteNode(nt.name))}}) = $(nt.store_type_uninit))
        con2 = if !isempty(T_params)
            :($SumTypes.constructor(::Type{<:$T_nameparam}, ::Type{Val{$(QuoteNode(nt.name))}}) where {$(T_params...)} = $(nt.store_type))
        end 
        push!(ex.args, con1, con2)
    end
    ex
end
