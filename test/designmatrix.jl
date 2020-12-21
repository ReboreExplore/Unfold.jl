##
using Test,DataFrames,StatsModels
using unfold
using MixedModels
using SparseArrays
tbl = DataFrame([1 4]',[:latency])
X = ones(size(tbl))
shouldBeNeg = zeros(4,4)
shouldBeNeg[1,:] = [1,0,0,1]
shouldBeNeg[2,:] = [0,1,0,0]
shouldBeNeg[3,:] = [0,0,1,0]
shouldBeNeg[4,:] = [0,0,0,1]

shouldBePos = zeros(4,4)
shouldBePos[1,:] = [0,0,0,0]
shouldBePos[2,:] = [1,0,0,0]
shouldBePos[3,:] = [0,1,0,0]
shouldBePos[4,:] = [0,0,1,0]

## test negative
basisfunction = firbasis(τ=(-3,0),sfreq = 1,name="testing")
timeexpandterm =  unfold.TimeExpandedTerm(FormulaTerm(Term,Term),basisfunction,:latency );
Xdc = unfold.time_expand(X,timeexpandterm,tbl)
@test all(isapprox.(Matrix(Xdc)[1:4,1:4], shouldBeNeg,atol=1e-15))

## Test Positive only
basisfunction = firbasis(τ=(1,4),sfreq = 1,name="testing")
timeexpandterm =  unfold.TimeExpandedTerm(FormulaTerm(Term,Term),basisfunction,:latency );
Xdc = unfold.time_expand(X,timeexpandterm,tbl)
println(Matrix(Xdc))

@test all(isapprox.(Matrix(Xdc)[1:4,1:4], shouldBePos,atol=1e-15))

# customized eventfields
tbl2 = tbl = DataFrame([1 4]',[:onset])

timeexpandterm_latency =  unfold.TimeExpandedTerm(FormulaTerm(Term,Term),basisfunction);
timeexpandterm_onset =  unfold.TimeExpandedTerm(FormulaTerm(Term,Term),basisfunction,eventfields=[:onset]);
Xdc = unfold.time_expand(X,timeexpandterm_onset,tbl)
@test_throws ArgumentError unfold.time_expand(X,timeexpandterm_latency,tbl)

## combining designmatrices
tbl = DataFrame([1 4]',[:latency])
X = ones(size(tbl))
basisfunction1 = firbasis(τ=(0,1),sfreq = 10,name="basis1")
basisfunction2 = firbasis(τ=(0,0.5),sfreq = 10,name="basis2")
f = @formula 0~1
Xdc1          = designmatrix(UnfoldLinearModel,f,tbl,basisfunction1)
Xdc2          = designmatrix(UnfoldLinearModel,f,tbl.+1,basisfunction2)

Xdc = Xdc1+Xdc2
@test size(Xdc.Xs,2) == size(Xdc1.Xs,2) + size(Xdc2.Xs,2)

if 1 == 0
    # not implemented yet
    basisfunction1 = firbasis(τ=(0,1),sfreq = 10,name="basis1")
    basisfunction2 = firbasis(τ=(0,0.5),sfreq = 10,name="basis2")

    tbl = DataFrame([1 4 10 15 20 22 31 37; 1 1 1 2 2 2 3 3; 1 2 3 1 2 3 1 2]',[:latency,:subject,:item])
    tbl2 = DataFrame([2 3 12 18 19 25 40 43; 1 1 1 2 2 2 3 3; 1 2 3 1 2 3 1 2]',[:latency,:subject,:itemB])
    y = Float64.([collect(range(1,stop=100))...])'
    categorical!(tbl,:subject)
    categorical!(tbl2,:itemB)
    categorical!(tbl,:item)
    #tbl.itemB = tbl.item
    f3 = @formula 0~1+(1|subject) + (1|item)
    f4 = @formula 0~1+(1|itemB)
    f4_wrong = @formula 0~1+(1|item)
    Xdc3          = designmatrix(UnfoldLinearMixedModel,f3,tbl,basisfunction1)
    Xdc4          = designmatrix(UnfoldLinearMixedModel,f4,tbl2,basisfunction2)
    Xdc4_wrong    = designmatrix(UnfoldLinearMixedModel,f4_wrong,tbl,basisfunction2)

    Xdc = Xdc3+Xdc4;
    @test typeof(Xdc.Xs[1]) <: SparseArrays.SparseMatrixCSC
    @test size(Xdc.Xs[1],2) == size(Xdc3.Xs[1],2) + size(Xdc4.Xs[1],2)
    @test length(Xdc.Xs) == 4 # one FeMat  + 3 ReMat
    @test_throws String Xdc3+Xdc4_wrong
    m = unfold.unfoldfit(UnfoldLinearMixedModel,Xdc,y);
end


# XXX concatenating of UnfoldLinearMixedModel designmatrices! Especially FeMat going to be more interesting....
df = unfoldfit(UnfoldLinearModel,Xdc,rand(1,size(Xdc.Xs,1)))
@test size(df.beta,2) == 17

## Speedtest
if 1==0
    x = collect(range(10,stop=10000,step=10))
    tbl = DataFrame(reshape(x,1000,1),[:latency])
    X = ones(size(tbl,1),3).*[1,2,3]'


    basisfunction = firbasis(τ=(0,1),sfreq = 100,name="test")
    term =  unfold.TimeExpandedTerm(Term,basisfunction,:latency );
    @time Xdc = Matrix(unfold.time_expand(X,term,tbl))
    
end
