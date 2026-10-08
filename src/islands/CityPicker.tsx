/**
 * Selector de ciudad con autocompletado (isla Preact, combobox accesible).
 * Escribe en un <input type="hidden" name={name}> el id de la ciudad.
 * Busca sin importar tildes: "villa maria", "rio cuarto"...
 */
import { useEffect, useId, useRef, useState } from "preact/hooks";

interface City {
  id: number;
  name: string;
  province_name: string;
}

interface Props {
  name: string;
  label: string;
  initialCity?: City | null;
  error?: string;
  hint?: string;
  required?: boolean;
}

export default function CityPicker({ name, label, initialCity = null, error, hint, required }: Props) {
  const id = useId();
  const listId = `${id}-list`;
  const [selected, setSelected] = useState<City | null>(initialCity);
  const [query, setQuery] = useState(initialCity ? display(initialCity) : "");
  const [results, setResults] = useState<City[]>([]);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const [loading, setLoading] = useState(false);
  const timer = useRef<number>();
  const controller = useRef<AbortController>();

  useEffect(() => () => window.clearTimeout(timer.current), []);

  function search(text: string) {
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(async () => {
      controller.current?.abort();
      controller.current = new AbortController();
      setLoading(true);
      try {
        const res = await fetch(`/api/ciudades?q=${encodeURIComponent(text)}`, { signal: controller.current.signal });
        const json = (await res.json()) as { results: City[] };
        setResults(json.results);
        setActive(json.results.length ? 0 : -1);
        setOpen(true);
      } catch {
        /* búsqueda cancelada o sin conexión */
      } finally {
        setLoading(false);
      }
    }, 200);
  }

  function choose(city: City) {
    setSelected(city);
    setQuery(display(city));
    setOpen(false);
  }

  return (
    <div class="relative flex flex-col gap-1.5">
      <label for={id} class="text-sm font-medium text-ink">
        {label}
      </label>
      <input type="hidden" name={name} value={selected ? String(selected.id) : ""} />
      <input
        id={id}
        type="text"
        role="combobox"
        autocomplete="off"
        aria-autocomplete="list"
        aria-expanded={open}
        aria-controls={listId}
        aria-activedescendant={open && active >= 0 ? `${listId}-${active}` : undefined}
        aria-invalid={error ? "true" : undefined}
        required={required}
        placeholder="Escribí tu ciudad, por ejemplo Villa María"
        value={query}
        class={[
          "h-11 w-full rounded-wl border bg-surface px-3 text-base text-ink placeholder:text-ink-muted/70",
          "focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/25",
          error ? "border-danger" : "border-line",
        ].join(" ")}
        onFocus={() => search(selected ? "" : query)}
        onInput={(event) => {
          const text = (event.currentTarget as HTMLInputElement).value;
          setQuery(text);
          setSelected(null);
          search(text);
        }}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown") {
            event.preventDefault();
            setOpen(true);
            setActive((i) => Math.min(i + 1, results.length - 1));
          } else if (event.key === "ArrowUp") {
            event.preventDefault();
            setActive((i) => Math.max(i - 1, 0));
          } else if (event.key === "Enter" && open && active >= 0 && results[active]) {
            event.preventDefault();
            choose(results[active]);
          } else if (event.key === "Escape") {
            setOpen(false);
          }
        }}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
      />

      {open && (
        <ul
          id={listId}
          role="listbox"
          class="absolute top-full z-20 mt-1 max-h-64 w-full overflow-auto rounded-wl border border-line bg-surface py-1 shadow-lg"
        >
          {results.length === 0 ? (
            <li class="px-3 py-2 text-sm text-ink-muted">{loading ? "Buscando…" : "No encontramos esa ciudad."}</li>
          ) : (
            results.map((city, index) => (
              <li
                id={`${listId}-${index}`}
                key={city.id}
                role="option"
                aria-selected={index === active}
                class={[
                  "cursor-pointer px-3 py-2 text-sm",
                  index === active ? "bg-seek-soft text-ink" : "text-ink hover:bg-surface-muted",
                ].join(" ")}
                onMouseDown={(event) => {
                  event.preventDefault();
                  choose(city);
                }}
              >
                <span class="font-medium">{city.name}</span>
                <span class="text-ink-muted">, {city.province_name}</span>
              </li>
            ))
          )}
        </ul>
      )}

      {hint && !error && <p class="text-xs text-ink-muted">{hint}</p>}
      {error && (
        <p class="text-sm text-danger" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

function display(city: City) {
  return `${city.name}, ${city.province_name}`;
}
