module SumTypes

export @sum_type, @match

using MLStyle: @match, @as_record

"""
    @sum_type(T, blk)

Create a sum type `T` with constructors in the codeblock `blk`. 

Examples:
*) An unparameterized sum type `Foo` with constructors `Bar` and `Baz`

    julia> @sum_type Foo begin
               Bar(::Int)
               Baz(::Float64)
           end

    julia> Bar(1)
    Foo(Bar(1))

*) 'The' `Either` sum type with constructors `Left` and `Right`

    julia> @sum_type Either{A, B} begin
               Left{A, B}(::A)
               Right{A, B}(::B)
           end

    julia> Left{Int, Int}(1)
    Either{Int64,Int64}(Left{Int64,Int64}(1))

    julia> Right{Int, Float64}(1.0)
    Either{Int64,Float64}(Right{Int64,Float64}(1.0))

*) A recursive `List` sum type with constructors `Nil` and `Cons`

    julia> @sum_type List{A} begin
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
    constructors = map(blk.args) do con::Expr
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
        struct_def = Expr(:struct, false, nameparam_constrained, 
                  Expr(:block, 
                       field_names..., 
                       :($nameparam($(field_names...)) where {$(T_params_constrained...)} = $(Expr(:new, T, Expr(:new, nameparam, field_names...))))))
        push!(out.args, struct_def)
        push!(out.args, :($(@__MODULE__).@as_record $name))
    end
    sum_struct_def = quote 
        struct $T
            data::Union{$((x -> x.nameparam).(constructors)...)}
            _1() = nothing
        end
    end
    push!(out.args, sum_struct_def)
    push!(out.args, :($(@__MODULE__).@as_record $T_name))
    esc(out)
end

end # module
