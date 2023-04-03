# @noinline err_inexhaustive(::Type{T}, variants) where{T} = throw(error(
#     "Inexhaustive @cases specification. Got cases $(variants), expected $(tags(T))"))
@noinline check_sum_type(::Type{T}) where {T} =
    is_sumtype(T) ? nothing : throw(error("@cases only works on SumTypes, got $T which is not a SumType"))
@noinline matching_error() = throw(error("Something went wrong during matching"))

@generated function assert_exhaustive(::Type{Val{tags}}, ::Type{Val{variants}}) where {tags, variants}
    ret = nothing
    for tag ∈ tags
        if tag ∉ variants 
            ret = error("Inexhaustive @cases specification. Got cases $(variants), expected $(tags)")
        end
    end
    for variant ∈ variants
        if variant ∉ tags
            ret = error("Unexpected variant $variant provided. Valid variants are: $(tags)")
        end
    end
    :($ret)
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
    deparameterize(x) = x isa Symbol ? x : x isa Expr && x.head == :curly ? x.args[1] : throw("Invalid variant name $x")

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
        (;variant=variant, rhs=rhs, fieldnames=fieldnames, iscall=iscall)
    end
    @gensym data
    @gensym _to_match
    @gensym con
    @gensym con_Union
    @gensym Typ
    @gensym nt
    variants = map(x -> x.variant, stmts)
    
    ex = :(if $get_tag($data) === $symbol_to_flag($Typ, $(QuoteNode(stmts[1].variant)));
               $(stmts[1].iscall ? :(($(stmts[1].fieldnames...),) =
                   $unwrap($data, $constructor($Typ, $Val{$(QuoteNode(stmts[1].variant))}), $variants_Tuple($Typ))  ) : nothing);
               $(stmts[1].rhs)
           end)
    Base.remove_linenums!(ex)
    pushfirst!(ex.args[2].args, lnns[1])
    to_push = ex.args
    for i ∈ 2:length(stmts)
        _if = :(if $get_tag($data) === $symbol_to_flag($Typ, $(QuoteNode(stmts[i].variant)));
                    $(stmts[i].iscall ? :(($(stmts[i].fieldnames...),) =
                        $unwrap($data, $constructor($Typ, $Val{$(QuoteNode(stmts[i].variant))}), $variants_Tuple($Typ))) : nothing);
                    $(stmts[i].rhs)
                end)
        _if.head = :elseif
        Base.remove_linenums!(_if)
        pushfirst!(_if.args[2].args, lnns[i])
        
        push!(to_push, _if)
        to_push = to_push[3].args
    end
    push!(to_push, :($matching_error()))
    quote
        let $data = $to_match
            $Typ = $typeof($data)
            $check_sum_type($Typ)
            $assert_exhaustive(Val{$tags($Typ)}, Val{$(Expr(:tuple, QuoteNode.(deparameterize.(variants))...))})
            $ex
        end
    end |> esc
end

