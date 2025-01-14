defmodule EfxCase do
  @moduledoc """
  Module for testing with effects.

  Binding effects in tests follows these principles:

  - By default, all effects of a module is bound to the default implementation.
  - We either bind all effect functions of a module or none.
    We cannot bind single functions (except the explicit use of :default).
    If we rebind only one effect and the other is called, we raise. 
  - A function is either bound without or with a specified number of expected calls.
    If a function has multiple binds, they are called in given order, until they satisfied their
    expected number of calls.
  - The number of expected calls is always veryified.

  ## Binding effects

  To bind effects one simply has to use this module and call
  the bind macro. Lets say we have the following effects implementation:

      defmodule MyModule do
        use Efx
    
        @spec get() :: list()
        defeffect get() do
           ...
        end
      end
    
  The following shows code that binds the effect:

      defmodule SomeTest do
        use EfxCase
    
        test "test something" do
          bind(MyModule, :get, fn -> [1,2,3] end)
          ...
        end
      end

  Instead of returning the value of the default implementation,
  `MyModule.get/0` returns `[1,2,3]`.

  ## Binding with an expected Number of Calls

  We can additionally define an expected number of calls. The expected
  number of calls is always verified - a test run will fail if
  it is not satisfied, as well as exceeded.

  We can define a number of expected calls as follows:


      defmodule SomeTest do
        use EfxCase
    
        test "test something" do
          expect(MyModule, :get, fn -> [1,2,3] end, calls: 2)
          ...
        end
      end

  In this case, we verify that the bound function `get/0` is called
  exactly twice.

  ## Binding globally

  Effect binding uses process dictionaries to find the right binding
  through-out the supervision-tree.
  As long as calling processes have the testing process that defines
  the binding as an ancestor, binding works. If we cannot ensure that,
  we can set binding to global. However, then the tests must be set
  to async to not interfere:

      defmodule SomeTest do
        use EfxCase, async: false
    
        test "test something" do
          bind(MyModule, :get, fn -> [1,2,3] end)
          ...
        end
      end


  ## Binding the same Function with multiple bind-Calls

  We can chain binds for the same functions. They then
  get executed until their number of expected calls is satisfied:

      defmodule SomeTest do
        use EfxCase
    
        test "test something" do
          bind(MyModule, :get,  fn -> [1,2,3] end, calls: 1)
          bind(MyModule, :get,  fn -> [] end, calls: 2)
          bind(MyModule, :get, fn -> [1,2] end)
          ...
        end
      end

  In this example the first binding of `get/0` gets called one time,
  then the second binding is used to replace the call two more times
  and the last get, specified without an expected number of calls,
  is used for the rest of the execution.

  ## Setup for many Tests

  If we want to setup the same binding for multiple tests we can do
  this as follows:

      defmodule SomeTest do
        use EfxCase

        setup_effects(MyModule,
           :get, fn -> [1,2,3] end
        )
    
        test "test something" do
          # test with mocked get
          ...
        end
      end


  ## Explicitly defaulting one Function in Tests

  While it is best practice to bind all function of a module or none,
  we can also default certain functions explicitly:

      defmodule MyModule do
        use EfxCase 
    
        @spec get() :: list()
        defeffect get() do
           ...
        end
    
        @spec put(any()) :: :ok
        defeffect put(any()) do
           ...
        end
      end
    

      defmodule SomeTest do
        use EfxCase
    
        test "test something" do
          bind(MyModule, :get, fn -> [1,2,3] end)
          bind(MyModule, :put, {:default, 0})
          ...
        end
      end

  While entirely leaving out `put/1` would result in an error
  (when called), we can tell the effects library to use it's
  default implementation. Note that defaulting can be combined
  with an expected number of calls.
  """

  require Logger

  alias EfxCase.MockState
  alias EfxCase.Internal

  defmacro __using__(opts) do
    async? = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async?)

      setup do
        pid =
          if unquote(async?) do
            self()
          else
            :global
          end

        Internal.init(pid)

        on_exit(fn ->
          Internal.verify_mocks!(pid)

          unless unquote(async?) do
            MockState.clean_globals()
          end
        end)
      end

      defp bind(effects_behaviour, key, fun, opts \\ []) do
        num = Keyword.get(opts, :calls)

        pid =
          if unquote(async?) do
            self()
          else
            :global
          end

        EfxCase.bind(pid, effects_behaviour, key, num, fun)
      end

      import EfxCase, only: [setup_effects: 2]
    end
  end

  defmacro setup_effects(effects_behaviour, stubs \\ []) do
    quote do
      setup do
        Enum.each(unquote(stubs), fn {k, v} ->
          bind(unquote(effects_behaviour), k, v)
        end)
      end
    end
  end

  def bind(pid, effects_behaviour, key, num \\ nil, fun) do
    {fun, arity} =
      case fun do
        {:default, _} = f ->
          f

        _ ->
          {:arity, arity} = Function.info(fun, :arity)
          {fun, arity}
      end

    MockState.add_fun(pid, effects_behaviour, key, arity, fun, num)
  end
end
