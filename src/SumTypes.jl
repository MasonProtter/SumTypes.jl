module SumTypes

export @sum_type, @case #@match

using MacroTools: MacroTools

function match end
function parent end
constructors(::Type{T}) where T = throw(error("$T is not a sum type"))

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
macro sum_type(T, blk::Expr, recur::Expr=:(recursive=false))
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
        @assert con_params == T_params "constructors currently must have same parameters as the sum type. Got $T and $(con.args[1])"
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
        (name=con_name, params=con_params, nameparam = con_nameparam, field_names=con_field_names, types=con_field_types)
    end
    out = Expr(:toplevel)
    foreach(constructors) do (name, params, nameparam, field_names, types)
        nameparam_constrained = isempty(params) ? name : :($name{$(T_params_constrained...)})
        field_names_typed = map(field_names, types) do name, type
            :($name :: $type)
        end
        struct_def = Expr(
            :struct, false, nameparam_constrained, 
            Expr(:block, 
                 field_names_typed..., 
                 :($nameparam($(field_names_typed...)) where {$(T_params_constrained...)} =
                   $(Expr(:new, T, Expr(:new, nameparam, field_names...))))))
        ex = quote
            $struct_def
            @inline $Base.iterate(x::$name, s = 1) = s ≤ fieldcount($name) ? (getfield(x, s), s + 1) : nothing
            $Base.indexed_iterate(x::$name, i::Int, state=1) = (Base.@_inline_meta; (getfield(x, i), i+1))
            $SumTypes.parent(::Type{<:$name}) = $T_name
            function $Base.show(io::IO, x::$name)
                print(io, "$(Base.typename($name).name)")
                isempty(x) && return nothing
                print(io, '(')
                for (i, elem) in enumerate(x)
                    show(io, elem)
                    i == fieldcount(typeof(x)) || print(io, ", ")
                end
                print(io, ')')
            end 
        end
        push!(out.args, ex)
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
        function $Base.show(io::IO, x::$T_name)
            print(io, "$(typeof(x)): ", x.data)
        end
        $SumTypes.constructors(::Type{<:$T_name}) = ($(con_names...),)
        function $SumTypes.match(f, x::$T) where {$(T_params...)}
            _x = x.data
            $(_unionsplit(con_nameparams, :(f(_x))))
        end
    end
    push!(out.args, ex)
    MacroTools.@capture(recur, recursive=use_recur_) ||
        throw("Malformed recur option. Expected `recursive=true` or `recursive=false`")
    if use_recur
        pushfirst!(out.args, f(sum_struct_def)) # hack to allow mutually recursive types
    end
    esc(out)
end

f(x) = :(try $x catch; nothing end) #split out to it's own function to to possible parsinf error?

"""
    @case T fdef

Define a pattern matcher `fdef` to deconstruct a `SumType`

Examples:

    @case Either f((x,)::Left)  = x + 1
    @case Either f((x,)::Right) = x - 1

Calling `f` on an `Either` type will use manually unrolled dispatch, rather than julia's automatic dynamic dispatch machinery.That is, it'll emit code that is just a series of if/else calls.
"""
macro case(T, fdef)
    d = MacroTools.splitdef(fdef)
    f = esc(d[:name])
    T = esc(T)
    quote
        $f(x::$T)= $SumTypes.match($f, x)
        $(:($fdef) |> esc)
    end
end

function _unionsplit(thetypes, call)
    MacroTools.@capture(call, f_(arg_))
    first_type, rest_types = Iterators.peel(thetypes)
    code = :(if $arg isa $first_type; $call end)
    the_args = code.args
    for next_type in rest_types
        clause = :(if $arg isa $next_type # use `if` so this parses, then change to `elseif`
                   $call
                   end)
        clause.head = :elseif
        push!(the_args, clause)
        the_args = clause.args
    end
    push!(the_args, :(@assert false))
    return code
end

iscomplete(matcher, ::Type{T}) where {T} = all(constructors(T)) do con
    hasmethod(matcher, (con,))
end

macro foo()
    ex = quote end
    x = :(x = 1)
    pushfirst!(ex.args, :(try $x catch _; end))
    ex
end 


end # module
