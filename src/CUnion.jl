module CUnion

using MacroTools

abstract type AbstractUnion end

function unionfields end

export AbstractUnion,unionfields

function reinterpret_cast(::Type{T}, x) where T
    s = max(sizeof(x), sizeof(T))
    a = Vector{UInt8}(undef, s)
    p = pointer(a)
    unsafe_store!(Ptr{typeof(x)}(p), x)
    unsafe_load(Ptr{T}(p))
end

function Base.getproperty(u::T, name::Symbol) where T <: AbstractUnion
    fields = unionfields(T)
    i = findfirst(((n, t),)->n == name, fields)
    if !isnothing(i)
        ft = fields[i].second
        isprimitivetype(ft) && sizeof(ft) == sizeof(T) && return reinterpret(ft, u)
        return reinterpret_cast(ft, u)
    end
    getfield(u, name)
end

function unionof(::Type{U}, x::T) where {U <: AbstractUnion,T}
    types = tuple(unique(last.(unionfields(U)))...)
    ret = findfirst(t->T == t, types)
    if isnothing(ret)
        error("$(typeof(x)) does not match any types of fields: $types")
    end
    if isprimitivetype(T) && sizeof(T) == sizeof(U)
        reinterpret(U, x)
    else
        reinterpret_cast(U, x)
    end
end

walkctx(x, inner, outer, ctx) = outer(x, ctx)
walkctx(x::Expr, inner, outer, ctx) = outer(Expr(x.head, map(inner, x.args)...), ctx)
postwalkctx(f, x, ctx) = walkctx(x, x->postwalkctx(f, x, isexpr(x, :struct) ? "$ctx#$(x.args[2])" : ctx), f, ctx)

function structflatten(lines, basety)
    defs = []
    result = postwalkctx(lines, "#$basety") do ex, ctx
        if @capture(ex,struct fname_Symbol lines__ end)
            fty = Symbol(ctx)
            def = Expr(:struct, false, fty, Expr(:block, lines...))
            push!(defs, def)
            :($fname::$fty)
        else
            ex
        end
    end
    return (Expr(:block, defs...) |> MacroTools.flatten, result)
end

macro union(ex)
    @capture(ex,
    struct T_Symbol
        rawbody_
    end
    ) || error("expected a struct definition without parameters: $ex")
    (defs, body) = structflatten(rawbody, T)
    @capture(body,lines__)
    members = map(lines) do line
        @capture(line,name_::type_) || error("expected a typed field definition: $line")
        (name, type)
    end |> x->(x...,)
    membersex = Expr(:tuple, map(members) do (name, type)
        :($(QuoteNode(name)) => $(type |> esc))
    end...)
    names = first.(members)
    if length(names) != length(unique(names))
        error("duplicate field name")
    end
    types = last.(members)
    typesex = Expr(:tuple, map(types) do t
        t |> esc
    end...)
    modulesym(x::Symbol) = Expr(:., Symbol(@__MODULE__) |> esc, QuoteNode(x))
    quote
        $(defs |> esc)
        maxsize = maximum($typesex) do t
            isbitstype(t) || error("not bits type: $t")
            sizeof(t)
        end * 8
        primitive type $T <: AbstractUnion maxsize end
        $(modulesym(:unionfields))(::Type{$(T |> esc)}) = $membersex
        $(T |> esc)($(:x |> esc)) = unionof($(T |> esc), $(:x |> esc))
        nothing
    end |> x->MacroTools.postwalk(unblock ∘ rmlines, x)
end

export @union

end # module
