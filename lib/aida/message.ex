defmodule Aida.Message do
  alias Aida.{Session, Message, Bot}
  alias Aida.Message.{TextContent, ImageContent}

  @type t :: %__MODULE__{
    session: Session.t,
    bot: Bot.t,
    content: TextContent.t | ImageContent.t,
    reply: [String.t]
  }

  defstruct session: %Session{},
            bot: %Bot{},
            content: %TextContent{},
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
    %{message | content: ImageContent.pull_and_store_image(content)}
  end

  def pull_and_store_image(%{content: %ImageContent{source_url: _, image_id: _}} = message) do
    message
  end

  @spec respond(message :: t, response :: String.t | map) :: t
  def respond(message, %{} = response) do
    respond(message, response[language(message)])
  end
  def respond(message, response) do
    new_reply = interpolate_vars(message, response)
    %{message | reply: message.reply ++ [new_reply]}
  end

  @spec get_session(message :: t, key :: String.t) :: Session.value
  def get_session(%{session: session}, key) do
    Session.get(session, key)
  end

  @spec put_session(message :: t, key :: String.t, value :: Session.value) :: t
  def put_session(%{session: session} = message, key, value) do
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

  defp lookup_var(message, key) do
    case message.bot |> Bot.lookup_var(message.session, key) do
      nil ->
        message.session |> Session.lookup_var(key)
      var ->
        var[language(message)]
    end
  end

  @spec interpolate_vars(message :: t, text :: String.t) :: String.t
  defp interpolate_vars(message, text, resolved_vars \\ []) do
    Regex.scan(~r/\$\{\s*([a-z_]*)\s*\}/, text, return: :index)
    |> List.foldr(text, fn (match, text) ->
      [{p_start, p_len}, {v_start, v_len}] = match
      var_name = text |> Kernel.binary_part(v_start, v_len)
      var_value =
        if var_name in resolved_vars do
          "..."
        else
          lookup_var(message, var_name) |> to_string
        end
      <<text_before :: binary-size(p_start), _ :: binary-size(p_len), text_after :: binary>> = text
      text_before <> interpolate_vars(message, var_value, [var_name | resolved_vars]) <> text_after
    end)
  end
end
