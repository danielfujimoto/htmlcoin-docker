# HTMLCOIN Node (Docker + Dokploy)

Repo com uma imagem Docker **multi-stage** que compila e executa o **HTMLCOIN Core** em **Ubuntu 18.04** (necessário por causa das toolchains e do Berkeley DB 4.8).  
Suporta usar **Dokploy** puxando este repositório diretamente do Git (opção A) ou rodar localmente com Docker Compose.

> ✅ Sem portas expostas por padrão (conecta para fora via P2P, mas não abre portas públicas).  
> ✅ Diretório de dados montado no host para persistir `wallet.dat`, `blocks/`, `chainstate/` etc.

---

## Estrutura

