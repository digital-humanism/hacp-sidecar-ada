## License

This repository contains the Ada/SPARK HACP sidecar implementation and reproduction surface, licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**, with Commercial Dual Licensing available for enterprise deployments, closed-source embedding, and OEM integration.

For commercial licensing inquiries, contact: `digital.humanism.collective@protonmail.com`.

### Relationship to other HACP repositories

| Repository | Purpose | License |
|---|---|---|
| [`hacp-spec`](https://github.com/digital-humanism/hacp-spec) | Open standard, schemas, and conformance material | CC BY 4.0 |
| [`humanist-core`](https://github.com/digital-humanism/humanist-core) | Reference SDK / project composition surface | AGPLv3 + commercial dual |
| [`hacp-sidecar`](https://github.com/digital-humanism/hacp-sidecar) | HACP enforcement sidecar implementation | AGPLv3 + commercial dual |
| `hacp-sidecar-ada` | Ada/SPARK HACP sidecar implementation and reproduction surface | AGPLv3 + commercial dual |

Canonical specification, schema, conformance, vector, and test-key material copied from `hacp-spec` retains its applicable project licensing and provenance. See [`test/matrix/PROVENANCE.md`](test/matrix/PROVENANCE.md).

External dependencies remain subject to their own upstream licenses.

### AGPLv3 notice for network deployment

Under AGPLv3 §13, any network-accessible deployment of this sidecar that serves external users requires the source code of the deployed version (including any modifications) to be made available to those users. Commercial licenses waive this requirement.
