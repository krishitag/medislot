import { useCallback, useEffect, useState } from "react";
import { api } from "./api.js";
import { useFlash } from "./App.jsx";

/** Load JSON from the API; returns [data, reload]. Errors go to the flash bar. */
export function useData(url) {
  const [data, setData] = useState(null);
  const flash = useFlash();
  const reload = useCallback(() => {
    api.get(url).then(setData).catch((e) => flash("err", e.message));
  }, [url, flash]);
  useEffect(reload, [reload]);
  return [data, reload];
}
