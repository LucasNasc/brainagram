defmodule Brainagram.Domain.Diagramming.Templates do
  @moduledoc """
  O texto com que um diagrama novo nasce.

  Página em branco é o pior começo: a pessoa não vê a animação nem lembra a
  sintaxe. Então o diagrama novo já vem com três nós e duas setas no tipo
  escolhido — o suficiente para dar play e trocar os nomes.

  O conteúdo sai no idioma da interface (`:pt`, `:en`, `:zh`, `:ru`, `:it`,
  `:ja` ou `:hi`). É texto do diagrama, não da interface: depois de criado,
  pertence à pessoa.
  """

  @type kind :: :sequence | :architecture
  @type lang :: :pt | :en | :zh | :ru | :it | :ja | :hi

  @langs [:pt, :en, :zh, :ru, :it, :ja, :hi]

  @doc "Os idiomas em que há modelo inicial."
  @spec langs() :: [lang()]
  def langs, do: @langs

  @spec starter(kind(), String.t(), lang()) :: String.t()
  def starter(kind, title, lang \\ :pt)

  def starter(:sequence, title, lang) do
    t = words(lang)

    """
    diagram sequence #{quote_title(title)}

    actor   user #{inspect(t.user)}
    service api  "API"
    database db  #{inspect(t.db)}

    step #{inspect(t.step)} {
      user -> api : #{t.request}
      api  -> db  : #{t.query}
      db  --> api : #{t.rows}
      api --> user : #{t.response}
    }
    """
  end

  def starter(:architecture, title, lang) do
    t = words(lang)

    """
    diagram architecture #{quote_title(title)}

    actor user #{inspect(t.user)}

    group "App" {
      service  api "API"
      database db  #{inspect(t.db)}
    }

    user -> api : HTTPS
    api  -> db  : SQL
    """
  end

  defp words(:en),
    do: %{
      user: "User",
      db: "Database",
      step: "Request",
      request: "request",
      query: "query",
      rows: "rows",
      response: "response"
    }

  defp words(:zh),
    do: %{
      user: "用户",
      db: "数据库",
      step: "请求",
      request: "请求",
      query: "查询",
      rows: "数据行",
      response: "响应"
    }

  defp words(:ru),
    do: %{
      user: "Пользователь",
      db: "База данных",
      step: "Запрос",
      request: "запрос",
      query: "выборка",
      rows: "строки",
      response: "ответ"
    }

  defp words(:it),
    do: %{
      user: "Utente",
      db: "Database",
      step: "Richiesta",
      request: "richiesta",
      query: "query",
      rows: "righe",
      response: "risposta"
    }

  defp words(:ja),
    do: %{
      user: "ユーザー",
      db: "データベース",
      step: "リクエスト",
      request: "リクエスト",
      query: "クエリ",
      rows: "行データ",
      response: "レスポンス"
    }

  defp words(:hi),
    do: %{
      user: "उपयोगकर्ता",
      db: "डेटाबेस",
      step: "अनुरोध",
      request: "अनुरोध",
      query: "क्वेरी",
      rows: "पंक्तियाँ",
      response: "प्रतिक्रिया"
    }

  defp words(_pt),
    do: %{
      user: "Usuário",
      db: "Banco de dados",
      step: "Requisição",
      request: "requisição",
      query: "consulta",
      rows: "linhas",
      response: "resposta"
    }

  # Aspas no título viram aspas tipográficas: dentro de "…" a DSL não escapa.
  defp quote_title(title) do
    clean = title |> to_string() |> String.replace("\"", "”") |> String.trim()
    ~s("#{clean}")
  end
end
