module CustomTest
using ControlSystems
import Base.Test: @test, @test_throws, Success, Failure, Error, with_handler
export @test, @test_throws, @test_approx_eq, @test_approx_eq_eps, @test_err, runtests, vecarray

type TestData
    nfail::Int
    nerr::Int
    failed::Bool
end
global TEST_DATA = TestData(0, 0, false)

term_cs = Base.tty_size()[2]
linebreak(lns::Int=0) = println(repeat("\n", lns), repeat("-", term_cs))

function run_test(file::AbstractString, term_cs=term_cs)
    print("* $file")
    include("$file.jl")
    spacing = repeat(" ", max(0, term_cs - length(file) - 8))
    if !TEST_DATA.failed
        println(spacing, "\033[1m\033[32mPASSED\033[0m")
    end
    TEST_DATA.failed = false
end

custom_handler(::Success) = nothing

function custom_handler(r::Failure)
    TEST_DATA.nfail += 1
    TEST_DATA.failed = true
    println("\n\033[1m\033[31mFAILED\033[0m:")
    if r.resultexpr != nothing
        println("\033[1m\033[31m$(r.resultexpr)\n in expression: $(r.expr)\033[0m")
    else
        println("\033[1m\033[31mIn expression: $(r.expr)\033[0m")
    end
    linebreak(1)
end

function custom_handler(r::Error)
    TEST_DATA.nerr += 1
    TEST_DATA.failed = true
    println("\n\033[1m\033[33mERRORED\033[0m:")
    showerror(STDOUT, r)
    linebreak(1)
end

info_string = """Julia Version: $(Base.VERSION), ($(Base.GIT_VERSION_INFO.date_string))
Commit $(Base.GIT_VERSION_INFO.commit_short)
$(Sys.MACHINE)"""

function runtests(tests)
    println(info_string, "\n")
    println("Running tests:")

    for test in tests
        with_handler(custom_handler) do
            run_test(test)
        end
    end

    linebreak(2)
    println("Failed: $(TEST_DATA.nfail), Errored: $(TEST_DATA.nerr)")
    if TEST_DATA.nerr > 0 || TEST_DATA.nfail > 0
        println("\033[1m\033[31mNOT OK\033[0m")
        linebreak()
        exit(1)
    else
        println("\033[1m\033[32mOK\033[0m")
        linebreak()
        exit(0)
    end
end

# Redefine test_approx_eq to actually use the framework
function test_approx_eq(va, vb, Eps, astr, bstr)
    va = Base.Test.approx_full(va)
    vb = Base.Test.approx_full(vb)
    if length(va) != length(vb)
        return false
    end
    diff = real(zero(eltype(va)))
    for i = 1:length(va)
        xa = va[i]; xb = vb[i]
        if isfinite(xa) && isfinite(xb)
            diff = max(diff, abs(xa-xb))
        elseif !isequal(xa,xb)
            return false
        end
    end

    if !isnan(Eps) && !(diff <= Eps)
        return false
    end
    return true
end
test_approx_eq(va, vb, astr, bstr) =
    test_approx_eq(va, vb, 1E4*length(va)*max(Base.Test.array_eps(va),
    Base.Test.array_eps(vb)), astr, bstr)
function test_approx_eq(va::StateSpace, vb::StateSpace, Eps, astr, bstr)
    fields = [:Ts, :nx, :ny, :nu, :inputnames, :outputnames, :statenames]
    for field in fields
        if getfield(va, field) != getfield(vb, field)
            return false
        end
    end
    diff = 0.0
    valfields = [:A, :B, :C, :D]
    for field in valfields
        mata = getfield(va, field)
        matb = getfield(vb, field)
        diff = max(diff, maximum(abs(mata - matb)))
    end
    if !isnan(Eps) && !(diff <= Eps)
        sdiff = string("|", astr, " - ", bstr, "| <= ", Eps)
        return false
    end
    return true
end
test_approx_eq(va::StateSpace, vb::StateSpace, astr, bstr) =
    test_approx_eq(va, vb, 1E4*length(va.A)*max(Base.Test.array_eps(va.A),
    Base.Test.array_eps(vb.A)), astr, bstr)

macro test_approx_eq(a, b)
    :(@test test_approx_eq($(esc(a)), $(esc(b)), $(string(a)), $(string(b))))
end
macro test_approx_eq_eps(a, b, meps)
    :(@test test_approx_eq($(esc(a)), $(esc(b)), $(esc(meps)), $(string(a)), $(string(b))))
end

test_approx_eq(a::TransferFunction, b::TransferFunction, astr, bstr) = (a ≈ b)

test_approx_eq(a::TransferFunction, b::TransferFunction, meps, astr, bstr) = isapprox(a, b, rtol=meps)

macro test_err(ex)
    quote
        @test_throws ErrorException $(esc(ex))
    end
end

function vecarray(T::Type, ny::Int,nx::Int, args::AbstractArray...)
    if ny*nx != length(args)
        error("Number of vectors must fit dimensions")
    end
    array = reshape(collect(Array{T,1},args),nx,ny)
    permutedims(array,[2,1])
end
vecarray{T}(ny::Int,nx::Int, args::AbstractArray{T}...) = vecarray(T, ny, nx, args...)

function vecarray(ny::Int,nx::Int, args::AbstractArray...)
    args2 = promote(args...)
    vecarray(eltype(args2[1]), ny, nx, args2...)
end

end  # module
