# AUTOR: Daniel Rueda Macías
# NIA: 559207
# FICHERO: servidor_gv.exs
# TIEMPO: 37 horas
# DESCRIPCION: Servidor que gestiona las vistas del sistema de almacenamiento
#              tolerante a fallos.
defmodule ServidorGV do

    @moduledoc """
        modulo del servicio de vistas
    """

    defstruct  num_vista: 0, primario: :undefined, copia: :undefined, 
               fallidos_primario: 0, fallidos_copia: 0,
               vista_valida: :undefined

    @periodo_latido 50

    @latidos_fallidos 4


   @doc """
        Generar un estructura de datos vista inicial
    """
    def vista_inicial() do
       %ServidorGV{}
    end

    @doc """
        Poner en marcha el servidor para gestión de vistas
    """
    @spec start(String.t, String.t) :: atom
    def start(host, nombre_nodo) do
        nodo = NodoRemoto.start(host, nombre_nodo,__ENV__.file, __MODULE__)

        Node.spawn_link(nodo, __MODULE__, :init_sv, [])

        nodo
    end

    # Estas 2 primeras deben ser defs para llamadas tipo (MODULE, funcion,[])
    def init_sv() do
        Process.register(self(), :servidor_gv)

        spawn(__MODULE__, :init_monitor, [self()]) # Otro proceso concurrente

        vista = vista_inicial
        bucle_recepcion(vista)
    end

    def init_monitor(pid_principal) do
        send(pid_principal, :procesa_situacion_servidores)
        Process.sleep(@periodo_latido)
        init_monitor(pid_principal)
    end


    defp bucle_recepcion(vista) do
        nueva_vista = receive do
                    {:latido, nodo_origen, n_vista} ->

                        # Para saber luego si primario falla.
                        if (vista.primario == nodo_origen) do
                            vista = Map.put(vista, :fallidos_primario, 0)
                        end

                        # Para saber luego si copia falla.
                        if (vista.copia == nodo_origen) do
                            vista = Map.put(vista, :fallidos_copia, 0)
                        end

                        # Si no hay primario se introduce el primer nodo que 
                        # llega.
                        if (vista.primario == :undefined) do
                            vista = Map.put(vista, :primario, nodo_origen)
                            vista = Map.put(vista, :num_vista, 
                                vista.num_vista + 1)
                        else

                            # Si no hay copia se introduce el primer nodo que 
                            # llega y que no sea el mismo que el primario.
                            if (vista.copia == :undefined && 
                                vista.primario != nodo_origen) do
                                vista = Map.put(vista, :copia, nodo_origen)
                                vista = Map.put(vista, :num_vista, 
                                    vista.num_vista + 1)
                            end
                        end

                        # Paso a de tentativa a válida.
                        if(vista.primario != :undefined && 
                            vista.copia != :undefined) do

                            if(vista.primario == nodo_origen && 
                                vista.num_vista == n_vista) do

                                vista = Map.put(vista, :vista_valida, 
                                    %{num_vista: vista.num_vista, 
                                    primario: vista.primario, copia: vista.copia})
                            end
                        end
                        send({:servidor_sa,nodo_origen},
                            {:vista_tentativa, %{num_vista: vista.num_vista,
                            primario: vista.primario, copia: vista.copia}, true})
                        vista
                    {:obten_vista, pid} ->
                        if (vista.vista_valida != :undefined) do
                            send(pid,{:vista_valida, vista.vista_valida ,true})
                        else
                            send(pid,{:vista_valida, vista.vista_valida ,false})
                        end
                        vista
                    :procesa_situacion_servidores ->
                        procesar_situacion_servidores(vista)
        end
        bucle_recepcion(nueva_vista)
    end

    defp procesar_situacion_servidores(vista) do
        # Si no hay primario no hay vista.
        if (vista.primario != :undefined) do
            vista = Map.put(vista, :fallidos_primario, 
                vista.fallidos_primario + 1)

            if (vista.copia != :undefined) do
                vista = Map.put(vista, :fallidos_copia, 
                    vista.fallidos_copia + 1) 
            end


            fallo_primario = vista.fallidos_primario == @latidos_fallidos
            fallo_copia = vista.fallidos_copia == @latidos_fallidos

            cond do
                # Fallan los dos.
                fallo_primario && fallo_copia ->
                    vista = vista_inicial
                # Falla el primario pero la copia no.
                fallo_primario && !fallo_copia ->
                    vista = Map.put(vista, :primario, vista.copia)
                    vista = Map.put(vista, :copia, :undefined)
                    vista = Map.put(vista, :num_vista, vista.num_vista + 1)
                    vista = Map.put(vista, :fallidos_primario, vista.fallidos_copia)
                    vista = Map.put(vista, :fallidos_copia, 0)
                # No falla el primario pero la copia si.
                !fallo_primario && fallo_copia ->
                    vista = Map.put(vista, :copia, :undefined)
                    vista = Map.put(vista, :num_vista, vista.num_vista + 1)
                    vista = Map.put(vista, :fallidos_copia, 0)
                # No falla ninguno.
                true -> # No hacemos nada.
            end
        end
        vista
    end
end
