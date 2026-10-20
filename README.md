# Smart Tech Rescue Android — edição comercial

Canal exclusivo da edição comercial do Smart Tech Rescue Android, separado do aplicativo offline permanente.

Até a homologação completa, o instalador comercial permanece em **release RASCUNHO** e não é distribuído a clientes.

A assinatura do MSI é **autoasssinada, sem confiança pública**. Ela não elimina avisos do Windows SmartScreen nem comprova a identidade comercial perante uma CA.

## Controles
- MSI com ProductName, UpgradeCode, pasta e atalhos próprios da edição comercial.
- O Windows de CI confirma instalação e desinstalação em máquina temporária. Não instala no computador do proprietário.
- A ativação comercial usa a API RSA do Worker de produção; os testes administrativos reais exigem o token privado e não devem ser automatizados com segredos em repositórios públicos.
- Usuários não devem acessar o feed de atualizações da edição offline para atualizar a comercial.
- Não publicar produção antes da verificação da interface WinForms, ciclo de licença paga/revogação e atualização/rollback reais.

Nenhum segredo RSA, token administrativo ou dado de cliente deve ser comitado aqui.
