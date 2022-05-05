module SumTypes

export @sum_type, @cases, Uninit

using MacroTools: MacroTools

function parent end
function constructors end
function constructors_Union end
is_sumtype(::Type{T}) where {T}   = false

struct Unsafe end
const unsafe = Unsafe()


struct Uninit end

"""
    @sum_type(T, blk)

Create a sum type `T` with constructors in the codeblock `blk`. 

Examples:
*) An unparameterized sum type `Foo` with constructors `Bar` and `Baz`

    @sum_type Foo begin
        Bar(::Int)
        Baz(::Float64)
    end

    julia> Bar(1)
    Foo(Bar(1))

*) 'The' `Either` sum type with constructors `Left` and `Right`

    @sum_type Either{A, B} begin
        Left{A, B}(::A)
        Right{A, B}(::B)
    end

    julia> Left{Int, Int}(1)
    Either{Int64,Int64}(Left{Int64,Int64}(1))

    julia> Right{Int, Float64}(1.0)
    Either{Int64,Float64}(Right{Int64,Float64}(1.0))

*) A recursive `List` sum type with constructors `Nil` and `Cons`

    @sum_type List{A} begin
        Nil{A}()
        Cons{A}(::A, ::List{A})
    end

    julia> Nil{Int}()
    List{Int64}(Nil{Int64}())

    julia> Cons{Int}(1, Cons{Int}(1, Nil{Int}()))
    List{Int64}(Cons{Int64}(1, List{Int64}(Cons{Int64}(1, List{Int64}(Nil{Int64}()))))) 
"""
macro sum_type(T, blk::Expr)
    @assert blk isa Expr && blk.head == :block
    T_name, T_params, T_params_constrained = if T isa Symbol
        T, [], []
    elseif T isa Expr && T.head == :curly
        T.args[1], (x -> x isa Expr && x.head == :(<:) ? x.args[1] : x).(T.args[2:end]), T.args[2:end]
    end
    filter!(x -> !(x isa LineNumberNode), blk.args)
    constructors = map(blk.args) do con_
        @assert isa(con_, Expr) "variants in sum type macro must be typed $(con_)(), not $(con_)"
        con::Expr = con_
        @assert con.head == :call
        con_name = con.args[1] isa Expr && con.args[1].head == :curly ? con.args[1].args[1] : con.args[1]
        con_params = (con.args[1] isa Expr && con.args[1].head == :curly) ? con.args[1].args[2:end] : []
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
        (
            name=con_name,
            params=con_params,
            nameparam = con_nameparam,
            field_names=con_field_names,
            types=con_field_types,
            params_uninit=con_params_uninit,
            params_constrained = con_params_constrained,
        )
    end
    out = Expr(:toplevel)
    converts = []
    foreach(constructors) do (name, params, nameparam, field_names, types, params_uninit, params_constrained)
        nameparam_constrained = isempty(params) ? name : :($name{$(params_constrained...)})
        T_uninit = isempty(T_params) ? T_name : :($T_name{$(params_uninit...)})
        T_init = isempty(T_params) ? T_name : :($T_name{$(T_params...)})
        field_names_typed = map(field_names, types) do name, type
            :($name :: $type)
        end
        struct_def = Expr(
            :struct, false, nameparam_constrained, 
            Expr(:block, 
                 field_names_typed..., 
                 :($nameparam(::$Unsafe, $(field_names_typed...)) where {$(params_constrained...)} =
                   $(Expr(:new, T_uninit, Expr(:new, nameparam, field_names...))))))
        maybe_no_param = if !isempty(params) && types == params
            :($name($(field_names_typed...)) where {$(params...)} = $nameparam($unsafe, $(field_names...)))
        end
        ex = quote
            $struct_def
            $nameparam($(field_names_typed...)) where {$(params_constrained...)} = $nameparam($unsafe, $(field_names...))
            $maybe_no_param
            @inline $Base.iterate(x::$name, s = 1) = s ≤ fieldcount($name) ? (getfield(x, s), s + 1) : nothing
            $Base.indexed_iterate(x::$name, i::Int, state=1) = (Base.@_inline_meta; (getfield(x, i), i+1))
            $SumTypes.parent(::Type{<:$name}) = $T_name
        end
        push!(out.args, ex)
        push!(converts, :($Base.convert(::Type{$T_init}, x::$T_uninit) where {$(T_params...)} = $(Expr(:new, T_init, :($getfield(x, :data))))))
        push!(converts, :($T_init(x::$T_uninit) where {$(T_params...)} = $(Expr(:new, T_init, :($getfield(x, :data))))))
    end

    con_nameparams = (x -> x.nameparam).(constructors)
    con_names      = (x -> x.name     ).(constructors)
    
    sum_struct_def = quote 
        struct $T
            data::Union{$(con_nameparams...)}
            _1() = nothing
        end
    end
    #

    ex = quote
        $sum_struct_def
        $SumTypes.constructors(::Type{<:$T_name}) = ($(con_names...),)
        $SumTypes.constructors_Union(::Type{<:$T_name}) = $Union{$(con_names...)}
        $SumTypes.is_sumtype(::Type{<:$T_name}) = true 
    end
    push!(out.args, ex)
    push!(out.args, Expr(:block, converts...))
    esc(out)
end


macro cases(to_match, block)
    @assert block.head == :block
    lnns = filter(block.args) do arg
        arg isa LineNumberNode
    end
    Base.remove_linenums!(block)
    while length(lnns) < length(block.args)
        push!(lnns, nothing)
    end
    stmts = map(block.args) do arg::Expr
        arg.head == :call && arg.args[1] == :(=>) || throw(error("Malformed case $arg"))
        lhs = arg.args[2]
        rhs = arg.args[3]
        if arg.args[2] isa Expr && arg.args[2].head == :call
            variant = arg.args[2].args[1]
            fieldnames = arg.args[2].args[2:end]
            iscall = true
        else
            variant = arg.args[2]
            fieldnames = []
            iscall = false
        end
        if !(variant isa Symbol)
            error("Invalid variant $variant")
        end
        (;variant, rhs, fieldnames, iscall)
    end
    @gensym data
    @gensym _to_match
    @gensym con
    @gensym con_Union
    variants = map(x -> x.variant, stmts)
    ex = :(if $data isa $(stmts[1].variant);
           $(stmts[1].iscall ? :(($(stmts[1].fieldnames...),) = $data) : nothing);
           $(stmts[1].rhs)
           end)
    Base.remove_linenums!(ex)
    pushfirst!(ex.args[2].args, lnns[1])
    to_push = ex.args
    for i ∈ 2:length(stmts)
        _if = :(if $data isa $(stmts[i].variant);
                $(stmts[i].iscall ? :(($(stmts[i].fieldnames...),) = $data) : nothing);
                $(stmts[i].rhs)
                end)
        _if.head = :elseif
        Base.remove_linenums!(_if)
        pushfirst!(_if.args[2].args, lnns[i])
        
        push!(to_push, _if)
        to_push = to_push[3].args
    end
    push!(to_push, :(error("Something went wrong during matching")))
    quote
        let $_to_match = $to_match
            $Union{$(variants...)} == $constructors_Union($typeof($_to_match)) ||
                $throw($error(
                    "Inexhaustic @cases specification. Got cases $($Union{$(variants...)}), expected $($constructors_Union($typeof($_to_match)))"))
            $is_sumtype($typeof($_to_match)) || $throw($error("$_to_match is not a SumType"))
            # $constructors_match($_to_match, $(variants...)) || $throw($error("Inexhaustic @cases specification"))
            $data = $getfield($_to_match, :data)
            $ex
        end
    end |> esc
end

end # module
