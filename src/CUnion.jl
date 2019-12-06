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
        return reinterpret_cast(ft, u)
    end
    getfield(u, name)
end

function unionof(::Type{T}, x) where T <: AbstractUnion
    types = tuple(unique(last.(unionfields(T)))...)
    ret = findfirst(t->x isa t, types)
    if isnothing(ret)
        error("$(typeof(x)) does not match any types of fields: $types")
    end
    reinterpret(T, x)
end

macro union(ex)
    @capture(ex,
    struct T_Symbol
        lines__
    end
    ) || error("expected a struct definition without parameters: $ex")
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
        maxsize = maximum($typesex) do t
            isbitstype(t) || error("not bits type: $t")
            sizeof(t)
        end * 8
        primitive type $T <: AbstractUnion maxsize end
        $(modulesym(:unionfields))(::Type{$(T |> esc)}) = $membersex
        $(T |> esc)($(:x |> esc)) = unionof($(T |> esc), $(:x |> esc))
        $(T |> esc)
    end
end

export @union

end # module
