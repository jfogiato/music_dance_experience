defmodule MusicDanceExperience.UsernameGenerator do
  @moduledoc """
  Generates Severance-themed suggested usernames.
  Format: <adjective><noun><2-digit number>
  e.g. "SeveredMilchick42", "LumonGoat07"
  """

  @adjectives ~w(
    Severed
    Refined
    Reintegrated
    Compliant
    Macrodata
    Lumon
    Perpetual
    Tempered
    Optics
    Wellness
    Mindful
    Loyal
    Waxy
    Cheerful
    Zealous
    Defiant
    Severable
    Innate
    Outward
    Goat
    Melon
    Dread
    Smiling
    Revolving
    Cold
    Sterile
    Corporate
    Harmonious
    Eager
    Obedient
    Blissful
    Curious
    Quiet
    Concerned
    Productive
    Refined
    Kier
    Cobel
    Helly
    Reghabi
  )

  @nouns ~w(
    Refiner
    Counselor
    Employee
    Outie
    Innie
    Architect
    Melon
    Waffle
    Goat
    Turtle
    Kier
    Milchick
    Cobel
    Graner
    Helly
    Ricken
    Petey
    Harmony
    Reghabi
    Handler
    Auditor
    Designate
    Detachment
    Perpetuity
    Wellness
    Corridor
    Elevator
    Breakroom
    Luncheon
    Handbook
    Incentive
    Party
    Rehearsal
    Portrait
    Keycard
    Badge
    Lanyard
    Binder
    Clipboard
    Wafer
    Omelet
    Melon
    Goat
    Turtle
    Music
    Dance
    Experience
  )

  @doc "Returns a random Severance-themed username suggestion."
  def generate do
    adj = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    num = :rand.uniform(99) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{adj}#{noun}#{num}"
  end
end
