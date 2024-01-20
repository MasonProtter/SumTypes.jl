
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

    if T isa Expr && T.head == :(<:)
        T, T_abstract = T.args
    else
        T, T_abstract = T, :(Any)
    end
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

    con_expr, con_structs = generate_constructor_exprs(T_name, T_params, T_params_constrained, T_nameparam, constructors)
    out = generate_sum_struct_expr(T, T_abstract, T_name, T_params, T_params_constrained, T_param_bounds, T_nameparam, constructors)
    Expr(:toplevel, con_structs, out, con_expr) 
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
                  store_type = Variant{name, (), Tuple{}},
                  store_type_uninit = Variant{name, (), Tuple{}},
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
                  store_type = :($Variant{$(QuoteNode(con_name)), ($(QuoteNode.(con_field_names)...),), Tuple{$(con_field_types...)}}),
                  store_type_uninit = :($Variant{$(QuoteNode(con_name)), ($(QuoteNode.(con_field_names)...),), Tuple{$(con_field_types_uninit...)}}),
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
    length(constructors) > typemax(UInt32) &&
        error("Too many variants in SumType, got $(length(constructors)). The current maximum number is $(typemax(UInt32) |> Int)")
    constructors
end

#------------------------------------------------------

function generate_constructor_exprs(T_name, T_params, T_params_constrained, T_nameparam, constructors)
    out = Expr(:toplevel)
    converts = []
    con_structs = Expr(:block)
    @gensym _tag _T x 
    enumerate_constructors = collect(enumerate(constructors))
    
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
                const $gname = $(Expr(:call, T_uninit, :($(nt.store_type_uninit)($unsafe)))) 
            end
            push!(out.args, ex)
        else
            field_names_typed = map(((name, type),) -> :($name :: $type), zip(field_names, field_types))
            T_con = :($gouter_type($(field_names_typed...)) where {$(params_constrained...)} =
                $(Expr(:call, T_uninit, :($store_type(($(field_names...),))),  )))

            T_con2 = if !all(x -> x ∈ (Any, :Any) ,field_types)
                s = Expr(:call, store_type, Expr(:tuple, [:($convert($field_type, $field_name))
                                                          for (field_type, field_name) ∈ zip(field_types, field_names)]...))
                :($gouter_type($(field_names...)) where {$(params_constrained...)} =
                    $(Expr(:call, T_uninit, s)))
            end
            maybe_no_param = if !isempty(params)
                :($gname($(field_names_typed...)) where {$(params...)} = $gouter_type($(field_names...)))
            end
            struct_def = Expr(:struct, false, gouter_type_constrained, Expr(:block, :(1 + 1)))
            ex = quote
                $T_con
                $T_con2
                $maybe_no_param
                $SumTypes.parent(::Type{<:$gname}) = $T_name
            end
            push!(con_structs.args, struct_def)
            push!(out.args, ex)
        end
        if true
            push!(converts, T_uninit => quote
                      $Base.convert(::$Type{$T_init}, $x::$T_uninit) where {$(T_params_constrained...)} = $T_init($unwrap($x)) 
                      $Base.convert(::$Type{<:$T_init}, $x::$T_uninit) where {$(T_params_constrained...)} = $T_init($unwrap($x)) 
                      (::$Type{<:$T_init})($x::$T_uninit) where {$(T_params_constrained...)} = $T_init($unwrap($x)) 
                      (::$Type{$T_init})($x::$T_uninit) where {$(T_params_constrained...)} = $T_init($unwrap($x)) 
                  end)
        end
    end
    unique!(x -> x[1], converts)
    append!(out.args, map(x -> x[2], converts))
    push!(out.args, quote
              $Base.convert(::$Type{$_T}, $x::$_T) where {$(T_params_constrained...), $_T <: $T_nameparam} = $x
              (::$Type{$_T})($x::$_T) where {$(T_params_constrained...), $_T <: $T_nameparam} = $x
          end)
    out, con_structs
end


#------------------------------------------------------

function generate_sum_struct_expr(T, T_abstract, T_name, T_params, T_params_constrained, T_param_bounds, T_nameparam, constructors)
    con_outer_types  = (x -> x.outer_type ).(constructors)
    con_gouter_types = (x -> x.gouter_type).(constructors)
    con_names        = (x -> x.name       ).(constructors)
    con_gnames       = (x -> x.gname      ).(constructors)
    store_types = (x -> x.store_type).(constructors)
    T_full = T

    sum_struct_def = Expr(:struct, false, Expr(:(<:), T_full, T_abstract),
                          Expr(:block, :(data :: ($Union){$(store_types...)}),  ))
    
    enumerate_constructors = collect(enumerate(constructors))

    ifnest_isvariant = mapfoldr(((cond, data), old) -> Expr(:if, cond, data, old),  enumerate_constructors, init=false) do (i, nt)
        :(unwrapped isa $(nt.store_type)), :($(QuoteNode(nt.name)) == s)
    end
    ifnest_get_tag = mapfoldr(((cond, data), old) -> Expr(:if, cond, data, old),  enumerate_constructors, init=:THIS_SHOULD_BE_UNREACHABLE) do (i, nt)
        :(unwrapped isa $(nt.store_type)), :($(QuoteNode(nt.name)))
    end
    
    only_define_with_params = if !isempty(T_params)
        @gensym x
        quote
            $SumTypes.constructors(::Type{<:$T_nameparam}) where {$(T_params_constrained...)} =
                $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.store_type for nt ∈ constructors)...)))
            $Base.adjoint(::Type{<:$T_nameparam}) where {$(T_params_constrained...)} =
                $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.value ? :($T_nameparam($(nt.gname))) : :($Converter{$T_nameparam, $(nt.gouter_type)}())
                                                            for nt ∈ constructors)...)))
            $SumTypes.variants_Tuple(::Type{<:$T_nameparam}) where {$(T_params_constrained...)} =
                $Tuple{$((nt.store_type for nt ∈ constructors)...)}
        end
    end

    @gensym _T
    @gensym st s
    ex = quote
        $sum_struct_def
        function $Base.propertynames(::$T_name)
            Base.depwarn("propertynames of a SumType is not intended to be used. Use `SumTypes.unwrap` if you need to access SumType internals", nothing)
            ()
        end
        function $Base.getproperty($st::$T_name, $s::Symbol)
            Base.depwarn("getproperty on a SumType is not intended to be used. Use `SumTypes.unwrap` if you need to access SumType internals", nothing)
            $Base.getfield($st, $s)
        end
        $SumTypes.is_sumtype(::Type{<:$T_name}) = true
        $SumTypes.constructors(::Type{<:$T_name}) =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.store_type_uninit for nt ∈ constructors)...)))
        
        $SumTypes.variants_Tuple(::Type{<:$T_name}) =
            $Tuple{$((nt.store_type_uninit for nt ∈ constructors)...)}
        
        $SumTypes.unwrap(x::$T_nameparam) where {$(T_params_constrained...)} = $getfield(x, :data)
        $Base.adjoint(::Type{<:$T_name}) =
            $NamedTuple{$tags($T_name)}($(Expr(:tuple, (nt.gname  for nt ∈ constructors)...)))
        $SumTypes.isvariant(x::$T_nameparam, s::Symbol) where {$(T_params_constrained...)} = let unwrapped = $unwrap(x)
            $ifnest_isvariant
        end
        $SumTypes.get_tag(x::$T_nameparam) where {$(T_params_constrained...)} = let unwrapped = $unwrap(x)
            $ifnest_get_tag
        end
        $SumTypes.tags(::Type{<:$T_name}) = $(Expr(:tuple, QuoteNode.(con_names)...))
        $Base.show(io::IO, x::$T_name) = $show_sumtype(io, x)
        $Base.show(io::IO, m::MIME"text/plain", x::$T_name) = $show_sumtype(io, m, x)

        Base.:(==)(x::$T_name, y::$T_name) = $Base.:(==)($unwrap(x), $unwrap(y))
        $only_define_with_params
    end
    foreach(constructors) do nt
        con1 = :($SumTypes.constructor(::Type{<:$T_name}, ::Type{Val{$(QuoteNode(nt.name))}}) = $(nt.store_type_uninit))
        con2 = if !isempty(T_params)
            :($SumTypes.constructor(::Type{<:$T_nameparam}, ::Type{Val{$(QuoteNode(nt.name))}}) where {$(T_params_constrained...)} = $(nt.store_type))
        end
        push!(ex.args, con1, con2)
    end
    ex
end

