import Foundation
import HealthOSCore
import HealthOSTerminal

@main
struct HealthOSCLIApp {
    static func main() async throws {
        // Inicializar o workspace com base no diretório atual
        let currentPath = FileManager.default.currentDirectoryPath
        let baseURL = URL(fileURLWithPath: currentPath)
        
        let workspace = WorkspaceManager(baseDir: baseURL)
        let menu = MenuCLI(workspaceManager: workspace)
        
        // Exibir intro com efeito visual via ANSI (assim como no menu.ts)
        await menu.intro()
        
        var isRunning = true
        let actions = menu.buildActions()
        
        while isRunning {
            menu.renderMenu(actions: actions)
            print("> ", terminator: "")
            
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                continue
            }
            
            if input == "0" {
                print("\u{001B}[31mEncerrando HealthOS CLI...\u{001B}[0m")
                isRunning = false
                break
            }
            
            if let action = actions.first(where: { $0.key.uppercased() == input.uppercased() }) {
                do {
                    try await action.run()
                } catch {
                    print("\n\u{001B}[31mErro durante a execução da tarefa: \(error)\u{001B}[0m")
                }
            } else {
                print("\n\u{001B}[33mOpção inválida. Digite a tecla correspondente à ação.\u{001B}[0m")
            }
        }
    }
}
