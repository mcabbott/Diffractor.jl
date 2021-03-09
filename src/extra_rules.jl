using StructArrays
using ChainRulesCore: NO_FIELDS

struct ∇getindex{T,S}
    xs::T
    i::S
end

function (g::∇getindex)(Δ)
    Δ′ = zero(g.xs)
    Δ′[g.i...] = Δ
    (ChainRulesCore.NO_FIELDS, Δ′, map(_ -> nothing, g.i)...)
end

function ChainRulesCore.rrule(g::∇getindex, Δ)
    g(Δ), Δ′′->(nothing, Δ′′[1][g.i...])
end

function ChainRulesCore.rrule(::typeof(getindex), xs::Array, i...)
    xs[i...], ∇getindex(xs, i)
end

function reversediff(f, xs...)
    y, f☆ = ∂⃖(f, xs...)
    return tuple(y, tail(f☆(dx(y)))...)
end

function reversediff_array(f, xs::Vector...)
    fieldarrays(StructArray(reversediff(f, x...) for x in zip(xs...)))
end

function reversediff_array(f, xs::Vector)
    fieldarrays(StructArray(reversediff(f, x) for x in xs))
end

function assert_gf(f)
    @assert sizeof(sin) == 0
end

function ChainRulesCore.rrule(::typeof(assert_gf), f)
    assert_gf(f), Δ->begin
        (NO_FIELDS, NO_FIELDS)
    end
end

#=
function ChainRulesCore.rrule(::typeof(map), f, xs::Vector...)
    assert_gf(f)
    primal, dual = reversediff_array(f, xs...)
    primal, Δ->begin
        (NO_FIELDS, NO_FIELDS, ntuple(i->map(*, getfield(dual, i), Δ), length(dual))...)
    end
end
=#

function ChainRulesCore.rrule(::typeof(*), A::AbstractMatrix{<:Real}, B::AbstractVector{<:Real})
    function times_pullback(Ȳ)
        return (NO_FIELDS, Ȳ * Base.adjoint(B), Base.adjoint(A) * Ȳ)
    end
    return A * B, times_pullback
end


function ChainRulesCore.rrule(::typeof(map), f, xs::Vector)
    assert_gf(f)
    arrs = reversediff_array(f, xs)
    primal = getfield(arrs, 1)
    primal, let dual = getfield(arrs, 2)
        Δ->(NO_FIELDS, NO_FIELDS, map(*, dual, Δ))
    end
end

function ChainRulesCore.rrule(::typeof(map), f, xs::Vector, ys::Vector)
    assert_gf(f)
    arrs = reversediff_array(f, xs, ys)
    primal = getfield(arrs, 1)
    primal, let dual = tail(arrs)
        Δ->(NO_FIELDS, NO_FIELDS, map(*, getfield(dual, 1), Δ), map(*, getfield(dual, 2), Δ))
    end
end

xsum(x::Vector) = sum(x)
function ChainRulesCore.rrule(::typeof(xsum), x::Vector)
    xsum(x), let xdims=size(x)
        Δ->(NO_FIELDS, fill(Δ, xdims...))
    end
end

struct NonDiffEven{N, O, P}; end
struct NonDiffOdd{N, O, P}; end

(::NonDiffOdd{N, O, P})(Δ) where {N, O, P} = (ntuple(_->Zero(), N), NonDiffEven{N, plus1(O), P}())
(::NonDiffEven{N, O, P})(Δ...) where {N, O, P} = (Zero(), NonDiffOdd{N, plus1(O), P}())
(::NonDiffOdd{N, O, O})(Δ) where {N, O} = ntuple(_->Zero(), N)

# This should not happen
(::NonDiffEven{N, O, O})(Δ...) where {N, O} = error()

@Base.pure function ChainRulesCore.rrule(::typeof(Core.apply_type), head, args...)
    Core.apply_type(head, args...), NonDiffOdd{plus1(plus1(length(args))), 1, 1}()
end

function ChainRulesCore.rrule(::typeof(Core.tuple), args...)
    Core.tuple(args...), Δ->Core.tuple(NO_FIELDS, Δ...)
end

@Base.aggressive_constprop function ChainRulesCore.rrule(::typeof(Core.getfield), s, field::Symbol)
    getfield(s, field), let P = typeof(s)
        @Base.aggressive_constprop Δ->begin
            nt = NamedTuple{(field,)}((Δ,))
            (NO_FIELDS, Composite{P, typeof(nt)}(nt), NO_FIELDS)
        end
    end
end

struct ∂⃖getfield{n, f}; end
@Base.aggressive_constprop function (::∂⃖getfield{n, f})(Δ) where {n,f}
    if @generated
        return Expr(:call, tuple, NO_FIELDS,
            Expr(:call, tuple, (i == f ? :(Δ) : DoesNotExist() for i = 1:n)...),
            NO_FIELDS)
    else
        return (NO_FIELDS, ntuple(i->i == f ? Δ : DoesNotExist(), n), NO_FIELDS)
    end
end

@Base.aggressive_constprop function ChainRulesCore.rrule(::typeof(Core.getfield), s, field::Int)
    getfield(s, field), ∂⃖getfield{nfields(s), field}()
end

ChainRulesCore.canonicalize(::ChainRulesCore.Zero) = ChainRulesCore.Zero()
