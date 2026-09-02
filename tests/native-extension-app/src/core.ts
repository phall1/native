import { Cmd, asciiBytes } from "@native-sdk/core";

export interface Model {
  readonly extensionResult: Uint8Array;
  readonly generatedResult: Uint8Array;
}

export type Msg =
  | { readonly kind: "extension_ok"; readonly value: Uint8Array }
  | { readonly kind: "extension_err"; readonly reason: Uint8Array }
  | { readonly kind: "generated_ok"; readonly value: Uint8Array }
  | { readonly kind: "generated_err"; readonly reason: Uint8Array };

// Two generic host requests, one per side of the runner's host-call mux:
// the extension reserves the `cockpit.` namespace and every other name
// stays with the runner's own binding. The fixture deliberately declares
// no typed service registry, because once one exists the frontend refuses
// any request name the registry does not spell (NS1067); an app-owned
// namespace is exactly the case that check cannot know about.
export function initialModel(): [Model, Cmd<Msg>] {
  return [
    { extensionResult: new Uint8Array(0), generatedResult: new Uint8Array(0) },
    Cmd.batch([
      Cmd.request("cockpit.snapshot", asciiBytes("request"), {
        key: "extension-request",
        ok: "extension_ok",
        err: "extension_err",
      }),
      Cmd.request("generated.echo", asciiBytes("service"), {
        key: "generated-request",
        ok: "generated_ok",
        err: "generated_err",
      }),
    ]),
  ];
}

export function update(model: Model, msg: Msg): Model {
  switch (msg.kind) {
    case "extension_ok":
      return { ...model, extensionResult: msg.value };
    case "extension_err":
      return { ...model, extensionResult: msg.reason };
    case "generated_ok":
      return { ...model, generatedResult: msg.value };
    case "generated_err":
      return { ...model, generatedResult: msg.reason };
  }
}
