

export PlusOperator, TimesOperator, mul_coefficients



struct PlusOperator{T,BI} <: Operator{T}
    ops::Vector{Operator{T}}
    bandwidths::BI
    function PlusOperator{T,BI}(opsin::Vector{Operator{T}},bi::BI) where {T,BI}
        n,m=size(first(opsin))
        for k=2:length(opsin)
            @assert size(opsin[k],1)==n && size(opsin[k],2)==m
        end
        new{T,BI}(opsin,bi)
    end
end

_size(::PlusOperator{<:Any, NTuple{2,InfiniteCardinal{0}}}, k) = InfiniteCardinal{0}()
_size(P, k) = size(first(P.ops),k)
Base.size(P::PlusOperator,k::Integer) = _size(P, k)

bandwidthsmax(ops) = mapreduce(bandwidths, (t1,t2) -> max.(t1, t2), ops, init = (-720, -720) #= approximate (-∞,-∞) =#)

PlusOperator(opsin::Vector{Operator{T}},bi::Tuple{Any,Any} = bandwidthsmax(opsin)) where {T} =
    PlusOperator{T,typeof(bi)}(opsin,bi)

bandwidths(P::PlusOperator) = P.bandwidths

israggedbelow(P::PlusOperator) = isbandedbelow(P) || all(israggedbelow,P.ops)

for (OP,mn) in ((:colstart,:min),(:colstop,:max),(:rowstart,:min),(:rowstop,:max))
    defOP = Meta.parse("default_"*string(OP))
    @eval function $OP(P::PlusOperator,k::Integer)
        if isbanded(P)
            $defOP(P,k)
        else
            mapreduce(op->$OP(op,k),$mn,P.ops)
        end
    end
end

function convert(::Type{Operator{T}},P::PlusOperator) where T
    if T==eltype(P)
        P
    else
        PlusOperator{T,typeof(P.bandwidths)}(Vector{Operator{T}}(P.ops),P.bandwidths)
    end
end

function promoteplus(opsin::Vector{Operator{T}}) where T
    ops = copy(opsin)
    # prune zero ops
    filter!(!iszeroop, ops)
    PlusOperator(promotespaces(ops))
end

for OP in (:domainspace,:rangespace)
    @eval $OP(P::PlusOperator) = $OP(first(P.ops))
end

domain(P::PlusOperator) = commondomain(P.ops)

_promote_eltypeof(As...) = _promote_eltypeof(As)
_promote_eltypeof(As::Union{Vector, Tuple}) = mapreduce(eltype, promote_type, As)

_extractops(A, ::Any) = [A]
_extractops(A::PlusOperator, ::typeof(+)) = A.ops

function +(A::Operator,B::Operator)
    v = Operator{_promote_eltypeof(A,B)}[_extractops(A, +); _extractops(B, +)]
    promoteplus(v)
end
# Optimization for 3-term sum
function +(A::Operator,B::Operator,C::Operator)
    v = Operator{_promote_eltypeof(A,B,C)}[_extractops(A,+); _extractops(B, +); _extractops(C, +)]
    promoteplus(v)
end

Base.stride(P::PlusOperator)=mapreduce(stride,gcd,P.ops)


function getindex(P::PlusOperator{T},k::Integer...) where T
    ret=P.ops[1][k...]::T
    for j=2:length(P.ops)
        ret+=P.ops[j][k...]::T
    end
    ret
end


for TYP in (:RaggedMatrix,:Matrix,:BandedMatrix,
            :BlockBandedMatrix,:BandedBlockBandedMatrix)
    @eval begin
        $TYP(P::SubOperator{T,PP,NTuple{2,BlockRange1}}) where {T,PP<:PlusOperator} =
            convert_axpy!($TYP,P)   # use axpy! to copy
        $TYP(P::SubOperator{T,PP}) where {T,PP<:PlusOperator} =
            convert_axpy!($TYP,P)   # use axpy! to copy
        $TYP(P::SubOperator{T,PP,NTuple{2,UnitRange{Int}}}) where {T,PP<:PlusOperator} =
            convert_axpy!($TYP,P)   # use axpy! to copy
    end
end

function BLAS.axpy!(α,P::SubOperator{T,PP},A::AbstractMatrix) where {T,PP<:PlusOperator}
    for op in parent(P).ops
        BLAS.axpy!(α, view(op,P.indexes[1],P.indexes[2]), A)
    end

    A
end


+(A::Operator,f::Fun) = A+Multiplication(f,domainspace(A))
+(f::Fun,A::Operator) = Multiplication(f,domainspace(A))+A
-(A::Operator,f::Fun) = A+Multiplication(-f,domainspace(A))
-(f::Fun,A::Operator) = Multiplication(f,domainspace(A))-A

for TYP in (:ZeroOperator,:Operator)
    @eval function +(A::$TYP,B::ZeroOperator)
        if spacescompatible(A,B)
            A
        else
            promotespaces(A,B)[1]
        end
    end
end
+(A::ZeroOperator,B::Operator) = B+A
+(Z1::ZeroOperator, Z2::ZeroOperator, Z3::ZeroOperator) = (Z1 + Z2) + Z3



# We need to support A+1 in addition to A+I primarily for matrix case: A+Matrix(I,2,2)
for OP in (:+,:-)
    @eval begin
        $OP(c::Union{UniformScaling,Number},A::Operator) =
            $OP(convert(Operator{_promote_eltypeof(A, c)},c),A)
        $OP(A::Operator,c::Union{UniformScaling,Number}) =
            $OP(A,convert(Operator{_promote_eltypeof(A, c)},c))
    end
end



## Times Operator

struct ConstantTimesOperator{B,T} <: Operator{T}
    λ::T
    op::B
    ConstantTimesOperator{B,T}(c,op) where {B,T} = new{B,T}(c,op)
end
function ConstantTimesOperator(c::Number,op::Operator{TT}) where TT<:Number
    T=promote_type(typeof(c),eltype(op))
    B=convert(Operator{T},op)
    ConstantTimesOperator{typeof(B),T}(T(c),B)
end

ConstantTimesOperator(c::Number,op::ConstantTimesOperator) =
    ConstantTimesOperator(c*op.λ,op.op)

@wrapperstructure ConstantTimesOperator
@wrapperspaces ConstantTimesOperator

convert(::Type{T},C::ConstantTimesOperator) where {T<:Number} = T(C.λ)*convert(T,C.op)

choosedomainspace(C::ConstantTimesOperator,sp::Space) = choosedomainspace(C.op,sp)


for OP in (:promotedomainspace,:promoterangespace),SP in (:UnsetSpace,:Space)
    @eval $OP(C::ConstantTimesOperator,k::$SP) = ConstantTimesOperator(C.λ,$OP(C.op,k))
end


function convert(::Type{Operator{T}},C::ConstantTimesOperator) where T
    if T==eltype(C)
        C
    else
        op=convert(Operator{T},C.op)
        ConstantTimesOperator{typeof(op),T}(T(C.λ),op)
    end
end

getindex(P::ConstantTimesOperator,k::Integer...) =
    P.λ*P.op[k...]


for TYP in (:RaggedMatrix,:Matrix,:BandedMatrix,
            :BlockBandedMatrix,:BandedBlockBandedMatrix)
    @eval begin
        $TYP(S::SubOperator{T,OP,NTuple{2,BlockRange1}}) where {T,OP<:ConstantTimesOperator} =
            convert_axpy!($TYP, S)
        $TYP(S::SubOperator{T,OP,NTuple{2,UnitRange{Int}}}) where {T,OP<:ConstantTimesOperator} =
            convert_axpy!($TYP, S)
        $TYP(S::SubOperator{T,OP}) where {T,OP<:ConstantTimesOperator} =
            convert_axpy!($TYP, S)
    end
end



BLAS.axpy!(α,S::SubOperator{T,OP},A::AbstractMatrix) where {T,OP<:ConstantTimesOperator} =
    unwrap_axpy!(α*parent(S).λ,S,A)





struct TimesOperator{T,BI} <: Operator{T}
    ops::Vector{Operator{T}}
    bandwidths::BI

    function TimesOperator{T,BI}(ops::Vector{Operator{T}},bi::BI) where {T,BI}
        # check compatible
        for k=1:length(ops)-1
            size(ops[k],2) == size(ops[k+1],1) || throw(ArgumentError("incompatible operator sizes"))
            spacescompatible(domainspace(ops[k]),rangespace(ops[k+1])) || throw(ArgumentError("imcompatible spaces at index $k"))
        end

        # remove TimesOperators buried inside ops
        timesinds = findall(x -> isa(x, TimesOperator), ops)
        if !isempty(timesinds)
            newops = copy(ops)
            for ind in timesinds
                splice!(newops, ind, ops[ind].ops)
            end
        else
            newops = ops
        end

        new{T,BI}(newops,bi)
    end
end

bandwidthssum(P, k::Integer) = bandwidthssum(P)[k]
bandwidthssum(P) = mapreduce(bandwidths, (t1, t2) -> t1 .+ t2, P, init = (0,0))
_bandwidthssum(A::Operator, B::Operator) = __bandwidthssum(bandwidths(A), bandwidths(B))
__bandwidthssum(A::NTuple{2,InfiniteCardinal{0}}, B::NTuple{2,InfiniteCardinal{0}}) = A
__bandwidthssum(A::NTuple{2,InfiniteCardinal{0}}, B) = A
__bandwidthssum(A, B::NTuple{2,InfiniteCardinal{0}}) = B
__bandwidthssum(A, B) = reduce((t1, t2) -> t1 .+ t2, (A, B), init = (0,0))

TimesOperator(ops::Vector{Operator{T}},bi::Tuple{N1,N2}) where {T,N1,N2} =
    TimesOperator{T,typeof(bi)}(ops,bi)

TimesOperator(ops::Vector{Operator{T}}) where {T} = TimesOperator(ops,bandwidthssum(ops))
TimesOperator(ops::Vector{OT}) where {OT<:Operator} =
    TimesOperator(convert(Vector{Operator{eltype(OT)}},ops),bandwidthssum(ops))

_extractops(A::TimesOperator, ::typeof(*)) = A.ops

function TimesOperator(A::Operator,B::Operator)
    v = Operator{_promote_eltypeof(A,B)}[_extractops(A, *); _extractops(B, *)]
    TimesOperator(v, _bandwidthssum(A, B))
end


==(A::TimesOperator,B::TimesOperator)=A.ops==B.ops

function convert(::Type{Operator{T}},P::TimesOperator) where T
    if T==eltype(P)
        P
    else
        TimesOperator(Operator{T}[P.ops;])
    end
end



function promotetimes(opsin::Vector{B},dsp) where B<:Operator
    ops=Vector{Operator{_promote_eltypeof(opsin)}}(undef,0)

    for k=length(opsin):-1:1
        if !isa(opsin[k],Conversion)
            op=promotedomainspace(opsin[k],dsp)
            if op==()
                # do nothing
            elseif isa(op,TimesOperator)
                for j=length(op.ops):-1:1
                    push!(ops,op.ops[j])
                end
                dsp=rangespace(op)
            else
                push!(ops,op)
                dsp=rangespace(op)
            end
        end
    end
    if isempty(ops)
        ConstantOperator(1.0,dsp)
    elseif length(ops)==1
        first(ops)
    else
        TimesOperator(reverse!(ops))  # change order in TImesOperator if this is slow
    end
end

promotetimes(opsin::Vector{B}) where {B<:Operator}=promotetimes(opsin,domainspace(last(opsin)))



domainspace(P::TimesOperator)=domainspace(last(P.ops))
rangespace(P::TimesOperator)=rangespace(first(P.ops))

domain(P::TimesOperator)=commondomain(P.ops)


bandwidths(P::TimesOperator) = P.bandwidths

israggedbelow(P::TimesOperator) = isbandedbelow(P) || all(israggedbelow,P.ops)

Base.stride(P::TimesOperator) = mapreduce(stride,gcd,P.ops)

for OP in (:rowstart,:rowstop)
    defOP=Meta.parse("default_"*string(OP))
    @eval function $OP(P::TimesOperator,k::Integer)
        if isbanded(P)
            return $defOP(P,k)
        end
        for j=eachindex(P.ops)
            k=$OP(P.ops[j],k)
        end
        k
    end
end

for OP in (:colstart,:colstop)
    defOP=Meta.parse("default_"*string(OP))
    @eval function $OP(P::TimesOperator, k::Integer)
        if isbanded(P)
            return $defOP(P, k)
        end
        for j=reverse(eachindex(P.ops))
            k=$OP(P.ops[j],k)
        end
        k
    end
end

getindex(P::TimesOperator,k::Integer,j::Integer) = P[k:k,j:j][1,1]
function getindex(P::TimesOperator,k::Integer)
    @assert isafunctional(P)
    P[1:1,k:k][1,1]
end

function getindex(P::TimesOperator,k::AbstractVector)
    @assert isafunctional(P)
    vec(Matrix(P[1:1,k]))
end

for TYP in (:Matrix, :BandedMatrix, :RaggedMatrix)
    @eval function $TYP(V::SubOperator{T,TO,Tuple{UnitRange{Int},UnitRange{Int}}}) where {T,TO<:TimesOperator}
        P = parent(V)

        if isbanded(P)
            if $TYP ≠ BandedMatrix
                return $TYP(BandedMatrix(V))
            end
        elseif isbandedblockbanded(P)
            N = block(rangespace(P), last(parentindices(V)[1]))
            M = block(domainspace(P), last(parentindices(V)[2]))
            B = P[Block(1):N, Block(1):M]
            return $TYP(view(B, parentindices(V)...), _colstops(V))
        end

        kr,jr = parentindices(V)

        (isempty(kr) || isempty(jr)) && return $TYP(Zeros, V)

        if maximum(kr) > size(P,1) || maximum(jr) > size(P,2) ||
            minimum(kr) < 1 || minimum(jr) < 1
            throw(BoundsError())
        end

        @assert length(P.ops) ≥ 2
        if size(V,1)==0
            return $TYP(Zeros, V)
        end


        # find optimal truncations for each operator
        # by finding the non-zero entries
        krlin = Matrix{Union{Int,InfiniteCardinal{0}}}(undef,length(P.ops),2)

        krlin[1,1],krlin[1,2]=kr[1],kr[end]
        for m=1:length(P.ops)-1
            krlin[m+1,1]=rowstart(P.ops[m],krlin[m,1])
            krlin[m+1,2]=rowstop(P.ops[m],krlin[m,2])
        end
        krlin[end,1]=max(krlin[end,1],colstart(P.ops[end],jr[1]))
        krlin[end,2]=min(krlin[end,2],colstop(P.ops[end],jr[end]))
        for m=length(P.ops)-1:-1:2
            krlin[m,1]=max(krlin[m,1],colstart(P.ops[m],krlin[m+1,1]))
            krlin[m,2]=min(krlin[m,2],colstop(P.ops[m],krlin[m+1,2]))
        end


        krl = Matrix{Int}(krlin)

        # Check if any range is invalid, in which case return zero
        for m=1:length(P.ops)
            if krl[m,1]>krl[m,2]
                return $TYP(Zeros, V)
            end
        end



        # The following returns a banded Matrix with all rows
        # for large k its upper triangular
        BA = convert($TYP{T}, P.ops[end][krl[end,1]:krl[end,2],jr])
        for m = (length(P.ops)-1):-1:1
            BA = convert($TYP{T}, P.ops[m][krl[m,1]:krl[m,2],krl[m+1,1]:krl[m+1,2]])*BA
        end

        $TYP{T}(BA)
    end
end

for TYP in (:BlockBandedMatrix, :BandedBlockBandedMatrix)
    @eval function $TYP(V::SubOperator{T,TO,Tuple{BlockRange1,BlockRange1}}) where {T,TO<:TimesOperator}
        P = parent(V)
        KR,JR = parentindices(V)

        @assert length(P.ops) ≥ 2
        if size(V,1)==0 || isempty(KR) || isempty(JR)
            return $TYP(Zeros, V)
        end

        if Int(maximum(KR)) > blocksize(P,1) || Int(maximum(JR)) > blocksize(P,2) ||
            Int(minimum(KR)) < 1 || Int(minimum(JR)) < 1
            throw(BoundsError())
        end


        # find optimal truncations for each operator
        # by finding the non-zero entries
        KRlin = Matrix{Union{Block,InfiniteCardinal{0}}}(undef,length(P.ops),2)

        KRlin[1,1],KRlin[1,2] = first(KR),last(KR)
        for m=1:length(P.ops)-1
            KRlin[m+1,1]=blockrowstart(P.ops[m],KRlin[m,1])
            KRlin[m+1,2]=blockrowstop(P.ops[m],KRlin[m,2])
        end
        KRlin[end,1]=max(KRlin[end,1],blockcolstart(P.ops[end],first(JR)))
        KRlin[end,2]=min(KRlin[end,2],blockcolstop(P.ops[end],last(JR)))
        for m=length(P.ops)-1:-1:2
            KRlin[m,1]=max(KRlin[m,1],blockcolstart(P.ops[m],KRlin[m+1,1]))
            KRlin[m,2]=min(KRlin[m,2],blockcolstop(P.ops[m],KRlin[m+1,2]))
        end


        KRl = Matrix{Block{1}}(KRlin)

        # Check if any range is invalid, in which case return zero
        for m=1:length(P.ops)
            if KRl[m,1]>KRl[m,2]
                return $TYP(Zeros, V)
            end
        end



        # The following returns a banded Matrix with all rows
        # for large k its upper triangular
        BA = convert($TYP, view(P.ops[end],KRl[end,1]:KRl[end,2],JR))
        for m = (length(P.ops)-1):-1:1
            BA = convert($TYP, view(P.ops[m],KRl[m,1]:KRl[m,2],KRl[m+1,1]:KRl[m+1,2]))*BA
        end

        convert($TYP, BA)
    end
end


## Algebra: assume we promote


for OP in (:(adjoint),:(transpose))
    @eval $OP(A::TimesOperator)=TimesOperator(reverse!(map($OP,A.ops)))
end

function *(A::Operator,B::Operator)
    if isconstop(A)
        promoterangespace(convert(Number,A)*B,rangespace(A))
    elseif isconstop(B)
        promotedomainspace(convert(Number,B)*A,domainspace(B))
    else
        promotetimes(Operator{_promote_eltypeof(A, B)}[_extractops(A, *); _extractops(B, *)])
    end
end



# Conversions we always assume are intentional: no need to promote

*(A::ConversionWrapper{TO1},B::ConversionWrapper{TO}) where {TO1<:TimesOperator,TO<:TimesOperator} =
    ConversionWrapper(TimesOperator(A.op,B.op))
*(A::ConversionWrapper{TO},B::Conversion) where {TO<:TimesOperator} =
    ConversionWrapper(TimesOperator(A.op,B))
*(A::Conversion,B::ConversionWrapper{TO}) where {TO<:TimesOperator} =
    ConversionWrapper(TimesOperator(A,B.op))

*(A::Conversion,B::Conversion) = ConversionWrapper(TimesOperator(A,B))
*(A::Conversion,B::TimesOperator) = TimesOperator(A,B)
*(A::TimesOperator,B::Conversion) = TimesOperator(A,B)
*(A::Operator,B::Conversion) =
    isconstop(A) ? promoterangespace(convert(Number,A)*B,rangespace(A)) : TimesOperator(A,B)
*(A::Conversion,B::Operator) =
    isconstop(B) ? promotedomainspace(convert(Number,B)*A,domainspace(B)) : TimesOperator(A,B)

^(A::Operator, p::Integer) = Base.power_by_squaring(A, p)


+(A::Operator) = A
-(A::Operator) = ConstantTimesOperator(-1,A)
-(A::Operator,B::Operator) = A+(-B)


function *(f::Fun, A::Operator)
    if isafunctional(A) && (isinf(bandwidth(A,1)) || isinf(bandwidth(A,2)))
        LowRankOperator(f,A)
    else
        TimesOperator(Multiplication(f,rangespace(A)),A)
    end
end

*(c::Number,A::Operator) = ConstantTimesOperator(c,A)
*(A::Operator,c::Number) = c*A

\(c::Number,B::Operator) = inv(c)*B
\(c::Fun,B::Operator) = inv(c)*B

/(B::Operator,c::Number) = B*inv(c)
/(B::Operator,c::Fun) = B*inv(c)





## Operations
for mulcoeff in [:mul_coefficients, :mul_coefficients!]
    @eval begin
        function $mulcoeff(A::Operator,b)
            n=size(b,1)
            ret = n>0 ? $mulcoeff(view(A,FiniteRange,1:n),b) : b
        end

        function $mulcoeff(A::TimesOperator,b)
            ret = b
            for k=length(A.ops):-1:1
                ret = $mulcoeff(A.ops[k],ret)
            end

            ret
        end
    end
end


function *(A::Operator, b)
    ds = domainspace(A)
    rs = rangespace(A)
    if isambiguous(ds)
        promotedomainspace(A,space(b))*b
    elseif isambiguous(rs)
        error("Assign spaces to $A before multiplying.")
    else
        Fun(rs,
            mul_coefficients(A,coefficients(b,ds)))
    end
end

mul_coefficients(A::PlusOperator,b::Fun) =
    mapreduce(x->mul_coefficients(x,b),+,A.ops)

*(A::Operator, b::AbstractMatrix{<:Fun}) = A*Fun(b)
*(A::Vector{<:Operator}, b::Fun) = map(a->a*b,convert(Array{Any,1},A))






## promotedomain


function promotedomainspace(P::PlusOperator{T},sp::Space,cursp::Space) where T
    if sp==cursp
        P
    else
        ops = [promotedomainspace(op,sp) for op in P.ops]
        promoteplus(Vector{Operator{_promote_eltypeof(ops)}}(ops))
    end
end


function choosedomainspace(P::PlusOperator,sp::Space)
    ret=UnsetSpace()
    for op in P.ops
        sp2=choosedomainspace(op,sp)
        if !isa(sp2,AmbiguousSpace)  # we will ignore this result in hopes another opand
                                     # tells us a good space
            ret=union(ret,sp2)
        end
    end
    ret
end



function promotedomainspace(P::TimesOperator,sp::Space,cursp::Space)
    if sp==cursp
        P
    elseif length(P.ops)==2
        P.ops[1]*promotedomainspace(P.ops[end],sp)
    else
        promotetimes([P.ops[1:end-1];promotedomainspace(P.ops[end],sp)])
    end
end



function choosedomainspace(P::TimesOperator,sp::Space)
    for op in P.ops
        sp=choosedomainspace(op,sp)
    end
    sp
end
