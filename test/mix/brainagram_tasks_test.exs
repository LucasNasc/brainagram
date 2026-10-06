defmodule Mix.Tasks.BrainagramTasksTest do
  @moduledoc "Spec 001, §9: `mix brainagram.fmt` e `mix brainagram.render` reusam o domínio."

  # Mix.shell é global: estes testes não rodam em paralelo com outros que o troquem.
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  @messy "diagram architecture \"X\"\nservice   api \"API\"\ndatabase pg\n  api -> pg : SELECT\n"

  describe "brainagram.fmt" do
    test "reescreve o arquivo na forma canônica", %{tmp_dir: dir} do
      file = Path.join(dir, "a.brain")
      File.write!(file, @messy)

      Mix.Tasks.Brainagram.Fmt.run([file])

      assert File.read!(file) ==
               "diagram architecture \"X\"\n\nservice  api \"API\"\ndatabase pg  \"Pg\"\n\napi -> pg : SELECT\n"
    end

    test "--check-formatted falha sem escrever", %{tmp_dir: dir} do
      file = Path.join(dir, "b.brain")
      File.write!(file, @messy)

      assert_raise Mix.Error, ~r/não estão formatados/, fn ->
        Mix.Tasks.Brainagram.Fmt.run(["--check-formatted", file])
      end

      assert File.read!(file) == @messy
    end

    test "arquivo com comentário é pulado sem --drop-comments", %{tmp_dir: dir} do
      file = Path.join(dir, "c.brain")
      File.write!(file, "# importante\n" <> @messy)

      Mix.Tasks.Brainagram.Fmt.run([file])

      assert File.read!(file) == "# importante\n" <> @messy
      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "comentários"
    end

    test "erro de sintaxe falha com a linha", %{tmp_dir: dir} do
      file = Path.join(dir, "d.brain")
      File.write!(file, "diagram sequence\nisso não\n")

      assert_raise Mix.Error, fn -> Mix.Tasks.Brainagram.Fmt.run([file]) end
      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ "d.brain:2:"
    end
  end

  describe "brainagram.render" do
    test "gera um SVG autocontido do estado final", %{tmp_dir: dir} do
      file = Path.join(dir, "fluxo.brain")
      File.write!(file, @messy)

      Mix.Tasks.Brainagram.Render.run([file])

      svg = File.read!(Path.join(dir, "fluxo.svg"))
      assert svg =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
      assert svg =~ "SELECT"
      assert svg =~ "bg-arrow-sync"
      refute svg =~ "var(--"
    end

    test "formato desconhecido é recusado", %{tmp_dir: dir} do
      file = Path.join(dir, "x.brain")
      File.write!(file, @messy)

      assert_raise Mix.Error, ~r/formato desconhecido/, fn ->
        Mix.Tasks.Brainagram.Render.run([file, "--format", "gif"])
      end
    end
  end
end
