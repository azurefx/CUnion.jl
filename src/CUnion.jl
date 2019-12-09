module CUnion

using MacroTools

abstract type AbstractUnion end

function unionfields end

export AbstractUnion,unionfields

@generated function ofsize_gen(::Type{T}) where T
    s = sizeof(T)
    return if s == 1
        UInt8
    elseif s == 2
        UInt16
    elseif s == 4
        UInt32
    elseif s == 8
        UInt64
    elseif s == 16
        UInt128
    else
        Nothing
    end
end

function ofsize(::Type{T}) where T
    ty = ofsize_gen(T)
    if ty !== Nothing
        return ty
    end
    s = sizeof(T)
    sym = gensym("Primitive$(8s)")
    ex = quote
        primitive type $sym $(8s) end
        ofsize(::Type{$T}) = $sym
        $sym
    end
    eval(ex)
end

function reinterpret_cast(::Type{T}, x) where T
    xbits = if isprimitivetype(typeof(x))
        reinterpret(ofsize(typeof(x)), x)
    else
        ref = Ref(x)
        GC.@preserve begin
            unsafe_load(Ptr{ofsize(typeof(x))}(pointer_from_objref(ref)))
        end
    end
    tbits = if sizeof(T) < sizeof(xbits)
        reinterpret(T, Core.Intrinsics.trunc_int(ofsize(T), xbits))
    elseif sizeof(T) > sizeof(xbits)
        reinterpret(T, Core.Intrinsics.zext_int(ofsize(T), xbits))
    else
        xbits
    end
    return if isprimitivetype(T)
        reinterpret(T, tbits)
    else
        ref = Ref(tbits)
        GC.@preserve begin
            unsafe_load(Ptr{T}(pointer_from_objref(ref)))
        end
    end
end

function Base.getproperty(u::T, name::Symbol) where T <: AbstractUnion
    fields = unionfields(T)
    i = findfirst(((n, t),)->n == name, fields)
    if !isnothing(i)
        ft = fields[i].second
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
    reinterpret_cast(U, x)
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
