defmodule Metastatic.NL.Adapters.Spanish.Tokenizer do
  @moduledoc """
  Linguistic tokenizer, part-of-speech tagger, and lemmatizer for Spanish.
  """

  @determiners ~w(
    el la los las un una unos unas este esta estos estas ese esa esos esas
    aquel aquella aquellos aquellas su sus mi mis tu tus nuestro nuestra nuestros nuestras
  )

  @pronouns ~w(
    yo tú él ella usted nosotros nosotras vosotros vosotras ellos ellas ustedes
    me te se nos os le les lo la los las mí ti sí
  )

  @prepositions ~w(
    a ante bajo con contra de desde durante en entre hacia hasta mediante
    para por según sin sobre tras versus vía
  )

  @conjunctions ~w(
    y e ni o u pero sino aunque porque pues si como mientras tanto
  )

  @auxiliaries ~w(
    ser es son fue fueron era eran ha han sido estar está están estaba estaban
    haber he has ha hemos han había habían
  )

  @participles ~w(
    escrito escrita escritos escritas hecho hecha hechos hechas dicho dicha dichos dichas
    visto vista vistos vistas puesto puesta puestos puestas abierto abierta abiertos abiertas
    muerto muerta muertos muertas roto rota rotos rotas impreso impresa impresos impresas
    resuelto resuelta resueltos resueltas
  )

  @doc """
  Determines the Universal POS tag for a Spanish word token.
  """
  @spec tag_pos(String.t()) :: atom()
  def tag_pos(word) when is_binary(word) do
    down = String.downcase(word)

    cond do
      down in @determiners ->
        :determiner

      down in @pronouns ->
        :pronoun

      down in @prepositions ->
        :preposition

      down in @conjunctions ->
        :conjunction

      down in @auxiliaries ->
        :auxiliary

      down in @participles or is_regular_participle?(down) ->
        :verb

      String.ends_with?(down, "mente") ->
        :adverb

      # Verb inflections
      String.ends_with?(down, ["ar", "er", "ir", "ando", "iendo", "aron", "ieron", "ará", "arán", "ó", "ió"]) ->
        :verb

      # Heuristic adjective endings
      String.ends_with?(down, ["al", "ble", "oso", "osa", "osos", "osas", "ivo", "iva"]) ->
        :adjective

      # Common nouns
      String.ends_with?(down, ["ción", "ciones", "sión", "dad", "tad", "mente", "dor", "dora"]) ->
        :noun

      true ->
        :noun
    end
  end

  @doc """
  Derives the canonical lemma for a Spanish word.
  """
  @spec lemmatize(String.t(), atom()) :: String.t()
  def lemmatize(word, pos) when is_binary(word) do
    down = String.downcase(word)

    case pos do
      :verb ->
        cond do
          down in ["es", "son", "fue", "fueron", "era", "eran", "sido", "sea"] -> "ser"
          down in ["está", "están", "estaba", "estaban", "estado"] -> "estar"
          down in ["ha", "han", "he", "has", "hemos", "había"] -> "haber"
          down in ["escrito", "escrita", "escritos", "escritas"] -> "escribir"
          down in ["hecho", "hecha", "hechos", "hechas"] -> "hacer"
          down in ["ejecutada", "ejecutado", "ejecutadas", "ejecutados"] -> "ejecutar"
          is_regular_participle?(down) -> lemmatize_participle(down)
          true -> down
        end

      :noun ->
        cond do
          String.ends_with?(down, "es") and not String.ends_with?(down, ["ción", "dad"]) ->
            String.slice(down, 0, String.length(down) - 2)

          String.ends_with?(down, "s") and not String.ends_with?(down, "ss") ->
            String.slice(down, 0, String.length(down) - 1)

          true ->
            down
        end

      _ ->
        down
    end
  end

  def is_regular_participle?(word) do
    String.ends_with?(word, ["ado", "ada", "ados", "adas", "ido", "ida", "idos", "idas"]) and
      String.length(word) > 4
  end

  defp lemmatize_participle(word) do
    cond do
      String.ends_with?(word, ["ado", "ada"]) ->
        String.slice(word, 0, String.length(word) - 3) <> "ar"

      String.ends_with?(word, ["ados", "adas"]) ->
        String.slice(word, 0, String.length(word) - 4) <> "ar"

      String.ends_with?(word, ["ido", "ida"]) ->
        String.slice(word, 0, String.length(word) - 3) <> "er"

      String.ends_with?(word, ["idos", "idas"]) ->
        String.slice(word, 0, String.length(word) - 4) <> "er"

      true ->
        word
    end
  end
end
