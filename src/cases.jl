# @noinline err_inexhaustive(::Type{T}, variants) where{T} = throw(error(
#     "Inexhaustive @cases specification. Got cases $(variants), expected $(tags(T))"))
@noinline check_sum_type(::Type{T}) where {T} =
    is_sumtype(T) ? nothing : throw(error("@cases only works on SumTypes, got $T which is not a SumType"))

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
    esc(_cases(to_match, block))
end

function _cases(to_match, block) 
    block.head == :block || error("The second argument to @cases must be a code block")
    lnns = filter(block.args) do arg
        arg isa LineNumberNode
    end
    # Base.remove_linenums!(block)

    stmts = []
    wildcard_stmt = Ref{Any}()
    
    foreach(enumerate(block.args)) do (i, arg)
        if arg isa LineNumberNode
            return nothing
        end
        arg.head == :call && arg.args[1] == :(=>) || error("Malformed case $arg")
        lhs = arg.args[2]
        rhs = arg.args[3]
        if isexpr(lhs, :call) # arg.args[2] isa Expr && arg.args[2].head == :call
            variant = lhs.args[1]
            fieldnames = lhs.args[2:end]
            iscall = true
        else
            variant = lhs
            fieldnames = []
            iscall = false
        end
        if variant isa Symbol
            if variant === :_
                if i == length(block.args)
                    wildcard_stmt[] = rhs
                else
                    error("The wildcard variant _ can only be used as the last option to @cases")
                end
            else
                push!(stmts, (;variant=variant, rhs=rhs, fieldnames=fieldnames, iscall=iscall))
            end
        elseif isexpr(variant, :vect)
            for subvariant ∈ variant.args
                if !(subvariant isa Symbol)
                    error("Invalid variant $subvariant from variant list $variant")
                end
                push!(stmts, (;variant=subvariant, rhs=rhs, fieldnames=fieldnames, iscall=iscall))
            end
        else
            error("Invalid variant $variant")
        end
    end
    isempty(lnns) && push!(lnns, nothing)
    while length(lnns) < length(stmts)
        push!(lnns, lnns[end])
    end
    
    @gensym data
    @gensym _to_match
    @gensym con
    @gensym con_Union
    @gensym Typ
    @gensym nt
    @gensym unwrapped
    variants = map(x -> x.variant, stmts)
    
    ex = :(if $unwrapped isa $Variant{$(QuoteNode(stmts[1].variant))}
               $(stmts[1].iscall ? :(($(stmts[1].fieldnames...),) = $unwrapped) : nothing);
               $(stmts[1].rhs)
           end)
    Base.remove_linenums!(ex)
    pushfirst!(ex.args[2].args, lnns[1])
    to_push = ex.args
    for i ∈ 2:length(stmts)
        _if = :(if $unwrapped isa $Variant{$(QuoteNode(stmts[i].variant))}
                     $(stmts[i].iscall ? :(($(stmts[i].fieldnames...),) = $unwrapped) : nothing);
                     $(stmts[i].rhs)
                 end)
        _if.head = :elseif
        Base.remove_linenums!(_if)
        pushfirst!(_if.args[2].args, lnns[i])
        
        push!(to_push, _if)
        to_push = to_push[3].args
    end
    # push!(to_push, :($matching_error()))
    deparameterize(x) = x isa Symbol ? x : x isa Expr && x.head == :curly ? x.args[1] : throw("Invalid variant name $x")
    if isdefined(wildcard_stmt, :x)
        push!(to_push, wildcard_stmt[])
        exhaustive_stmt = nothing
    else
        exhaustive_stmt = :($assert_exhaustive(Val{$tags($Typ)},
                                               Val{$(Expr(:tuple, QuoteNode.(deparameterize.(variants))...))}))
    end
    quote
        let $data = $to_match
            $Typ = $typeof($data)
            $check_sum_type($Typ)
            $exhaustive_stmt
            $unwrapped = $unwrap($data)
            $ex
        end
    end
end
