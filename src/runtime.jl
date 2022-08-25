using ChainRulesCore
struct DiffractorRuleConfig <: RuleConfig{Union{HasReverseMode,HasForwardsMode}} end

@Base.constprop :aggressive accum(a, b) = a + b
@Base.constprop :aggressive accum(a::Tuple, b::Tuple) = map(accum, a, b)
@Base.constprop :aggressive @generated function accum(x::NamedTuple, y::NamedTuple)
    fnames = union(fieldnames(x), fieldnames(y))
    gradx(f) = f in fieldnames(x) ? :(getfield(x, $(quot(f)))) : :(ZeroTangent())
    grady(f) = f in fieldnames(y) ? :(getfield(y, $(quot(f)))) : :(ZeroTangent())
    Expr(:tuple, [:($f=accum($(gradx(f)), $(grady(f)))) for f in fnames]...)
end
@Base.constprop :aggressive accum(a, b, c, args...) = accum(accum(a, b), c, args...)
@Base.constprop :aggressive accum(a::NoTangent, b) = b
@Base.constprop :aggressive accum(a, b::NoTangent) = a
@Base.constprop :aggressive accum(a::NoTangent, b::NoTangent) = NoTangent()

using ChainRulesCore: add!!, is_inplaceable_destination

struct AccumThunk{T} <: AbstractThunk
    value::T
end
accumthunk(a) = is_inplaceable_destination(a) ? AccumThunk(a) : a

@inline ChainRulesCore.unthunk(a::AccumThunk) = a.value

# An AccumThunk always wraps an array which is legal to mutate:

accum(a::AccumThunk, b::AbstractArray) = accumthunk(add!!(a.value, b))
accum(a::AbstractArray, b::AccumThunk) = accumthunk(add!!(b.value, a))

accum(a::AccumThunk, b::AbstractThunk) = accumthunk(add!!(a.value, b))
accum(a::AbstractThunk, b::AccumThunk) = accumthunk(add!!(b.value, a))

function accum(a::AccumThunk, b::AccumThunk)
    if is_inplaceable_destination(a.value)
        accumthunk(add!!(a.value, b.value))
    else
        accumthunk(add!!(b.value, a.value))
    end
end

# Any array created by `accum` is new, hence safe:

accum(a::AbstractArray, b::AbstractArray) = accumthunk(a + b)
# accum(a::AbstractThunk, b::AbstractArray) = accumthunk(unthunk(a) + b)
# accum(a::AbstractArray, b::AbstractThunk) = accumthunk(a + unthunk(b))
# accum(a::AbstractThunk, b::AbstractThunk) = accum(unthunk(a) + unthunk(b))

# (That's 9 methods above, all pairs from [AbstractArray, AbstractThunk, AccumThunk])

# Perhaps the result of unthunk is always safe, too:

accum(a::AbstractThunk, b::AbstractArray) = accumthunk(add!!(unthunk(a), b))
accum(a::AbstractArray, b::AbstractThunk) = accumthunk(add!!(unthunk(b), a))

accum(a::InplaceableThunk, b::AbstractThunk) = accumthunk(add!!(unthunk(b), a))
accum(a::AbstractThunk, b::InplaceableThunk) = accumthunk(add!!(unthunk(a), b))
accum(a::AbstractThunk, b::AbstractThunk) = accum(accumthunk(unthunk(a)) + accumthunk(unthunk(b)))
function accum(a::InplaceableThunk, b::InplaceableThunk)
    a_val = unthunk(a)
    if is_inplaceable_destination(a_val)
        accumthunk(add!!(a_val, b))
    else
        accumthunk(add!!(unthunk(b), a_val))
    end
end

# Should be 16 methods, all pairs from [AbstractArray, AbstractThunk, AccumThunk, InplaceableThunk]),
# the last 4 solve ambiguities:

accum(a::AccumThunk, b::InplaceableThunk) = accumthunk(add!!(a.value, b))
accum(a::InplaceableThunk, b::AccumThunk) = accumthunk(add!!(b.value, a))

accum(a::InplaceableThunk, b::AbstractArray) = accumthunk(add!!(unthunk(a), b))
accum(a::AbstractArray, b::InplaceableThunk) = accumthunk(add!!(unthunk(b), a))
