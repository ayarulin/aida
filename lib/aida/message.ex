defmodule Aida.Message do
  alias Aida.{Session, Message, Bot}
  alias Aida.Message.{TextContent, ImageContent, UnknownContent, Content}

  @type t :: %__MODULE__{
    session: Session.t,
    bot: Bot.t,
    content: TextContent.t | ImageContent.t | UnknownContent.t,
    sensitive: boolean,
    reply: [String.t]
  }

  defstruct session: %Session{},
            bot: %Bot{},
            content: %TextContent{},
            sensitive: false,
            reply: []

  @spec new(content :: String.t, bot :: Bot.t, session :: Session.t) :: t
  def new(content, %Bot{} = bot, session \\ Session.new) do
    %Message{
      session: session,
      bot: bot,
      content: %TextContent{ text: content }
    }
  end

  @spec new_from_image(source_url :: String.t, bot :: Bot.t, session :: Session.t) :: t
  def new_from_image(source_url, %Bot{} = bot, session \\ Session.new) do
    %Message{
      session: session,
      bot: bot,
      content: %ImageContent{source_url: source_url}
    }
  end

  @spec new_unknown(bot :: Bot.t, session :: Session.t) :: t
  def new_unknown(%Bot{} = bot, session \\ Session.new) do
    %Message{
      session: session,
      bot: bot,
      content: %UnknownContent{}
    }
  end

  def text_content(%{content: %TextContent{text: text}}) do
    text
  end

  def text_content(_) do
    ""
  end

  def image_content(%{content: %ImageContent{} = content}) do
    content
  end

  def image_content(_) do
    nil
  end

  def image_id(%{content: %ImageContent{source_url: _, image_id: nil}}) do
    :not_available
  end

  def image_id(%{content: %ImageContent{source_url: _, image_id: image_id}}) do
    image_id
  end

  def image_id(_) do
    :not_image_content
  end

  def pull_and_store_image(%{content: %ImageContent{source_url: _, image_id: nil} = content} = message) do
    %{message | content: ImageContent.pull_and_store_image(content, message.bot.id, message.session.id)}
  end

  def pull_and_store_image(%{content: %ImageContent{source_url: _, image_id: _}} = message) do
    message
  end

  @spec respond(message :: t, response :: String.t | map) :: t
  def respond(message, %{} = response) do
    respond(message, response[language(message)])
  end
  def respond(message, response) do
    response = interpolate_expressions(message, response)
    response = interpolate_vars(message, response)
    %{message | reply: message.reply ++ [response]}
  end

  @spec get_session(message :: t, key :: String.t) :: Session.value
  def get_session(%{session: session}, key) do
    Session.get(session, key)
  end

  @spec put_session(message :: t, key :: String.t, value :: Session.value) :: t
  def put_session(%{session: session, bot: bot} = message, key, value, options \\ []) do
    encrypted = Keyword.get(options, :encrypted, false)
    value =
      if encrypted do
        Bot.encrypt(bot, value |> Poison.encode!)
      else
        value
      end

    %{message | session: Session.put(session, key, value)}
  end

  @spec new_session?(message :: t) :: boolean
  def new_session?(%{session: session}) do
    Session.is_new?(session)
  end

  @spec language(message :: t) :: Session.value
  def language(message) do
    get_session(message, "language")
  end

  def words(%{content: %TextContent{text: text}}) do
    Regex.scan(~r/\w+/u, text |> String.downcase) |> Enum.map(&hd/1)
  end

  def words(_), do: []

  def lookup_var(message, key) do
    case message.bot |> Bot.lookup_var(message, key) do
      nil ->
        message.session |> Session.lookup_var(key)
      var ->
        var[language(message)]
    end
  end

  defp display_var(value) when is_list(value) do
    value |> Enum.join(", ")
  end

  defp display_var(:not_found) do
    ""
  end

  defp display_var(value) do
    value |> to_string
  end

  @spec interpolate_vars(message :: t, text :: String.t) :: String.t
  defp interpolate_vars(message, text, resolved_vars \\ []) do
    Regex.scan(~r/\$\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}/, text, return: :index)
    |> List.foldr(text, fn (match, text) ->
      [{p_start, p_len}, {v_start, v_len}] = match
      var_name = text |> Kernel.binary_part(v_start, v_len)
      var_value =
        if var_name in resolved_vars do
          "..."
        else
          lookup_var(message, var_name) |> display_var
        end
      <<text_before :: binary-size(p_start), _ :: binary-size(p_len), text_after :: binary>> = text
      text_before <> interpolate_vars(message, var_value, [var_name | resolved_vars]) <> text_after
    end)
  end

  @spec interpolate_expressions(message :: t, text :: String.t) :: String.t
  def interpolate_expressions(message, text) do
    Regex.scan(~r/\{\{(.*)\}\}/U, text, return: :index)
    |> List.foldr(text, fn (match, text) ->
      [{p_start, p_len}, {v_start, v_len}] = match
      expr = text |> Kernel.binary_part(v_start, v_len)
      expr_result =
        try do
          Aida.Expr.parse(expr)
          |> Aida.Expr.eval(message |> expr_context(lookup_raises: true))
          |> display_var
        rescue
          error -> "[ERROR: #{Exception.message(error)}]"
        end

      <<text_before :: binary-size(p_start), _ :: binary-size(p_len), text_after :: binary>> = text
      text_before <> expr_result <> text_after
    end)
  end

  def expr_context(message, options \\ []) do
    lookup_raises = options[:lookup_raises]
    var_lookup = fn name ->
      case Message.lookup_var(message, name) do
        :not_found ->
          if lookup_raises do
            raise Aida.Expr.UnknownVariableError.exception(name)
          else
            nil
          end
        value -> value
      end
    end

    context = options
      |> Keyword.merge([var_lookup: var_lookup])
      |> Aida.Expr.Context.new

    Bot.expr_context(message.bot, context, options)
  end

  def type(%Message{content: content}) do
    content |> Content.type()
  end

  def raw(%Message{content: content}) do
    content |> Content.raw()
  end

  def mark_sensitive(message) do
    %{message | sensitive: true}
  end
end
